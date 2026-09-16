# BLE Emission Redesign — Architecture Review & Implementation Plan

**Date:** 2026-04-28
**Author:** Senior iOS / Bluetooth Specialist Review
**Status:** Final — ready for implementation

---

## 1. Current State: Why Emission Still Fails

The BEACON_EMISSION_FAILURE_ANALYSIS.md identified Issues 1–6. Issues 2, 3, and 5 have been partially
addressed in the current working branch. However, emission is still not happening. Here is why.

### 1.1 The Visible Flow vs. What Actually Happens

When the user runs `advertise` on macOS 11+, the current flow is:

```
run()
  └─ checkBluetoothCapabilities()   ← creates CBPeripheralManager(delegate: nil)
  └─ checkPermissions()             ← reads CBPeripheralManager.authorization
  └─ PrivateKeyIBeaconStrategy.startEmission()
       └─ CBPeripheralManager(delegate: self)
       └─ peripheralManagerDidUpdateState → .poweredOn
       └─ startAdvertising([kCBAdvDataAppleBeaconKey: payload])
       └─ peripheralManagerDidStartAdvertising(error: nil)   ← always nil
       └─ prints "Broadcasting..." ← MISLEADING SUCCESS
```

CoreBluetooth reports `error == nil` at `peripheralManagerDidStartAdvertising`. The tool prints success.
No beacon is actually on air. This is the "silent success" failure mode documented in Issue 1.

The user sees success output, but no scanner (iOS or otherwise) ever detects the beacon.

### 1.2 Root Cause Hierarchy (updated)

| Priority | Layer | Problem |
|---|---|---|
| P0 | OS | `bluetoothd` drops `0x4C` frames — only Xcode Archive bypasses this |
| P1 | Architecture | Pre-flight `SystemCapabilityDetector` is unreliable and creates spurious CBPeripheralManagers |
| P2 | Architecture | No self-verification: tool reports "broadcasting" but never confirms OTA emission |
| P3 | Code | `EnhancediBeaconStrategy` is dead code — min target is macOS 11.0 |
| P4 | Code | Strategy cascade uses OS version gate (`>= 11`) instead of runtime capability test |
| P5 | Code | `canEmit()` in all strategies uses `CBPeripheralManager(delegate: nil)` — state is always `.unknown` at t=0.5s |

---

## 2. Architectural Diagnosis

### 2.1 The Pre-flight Anti-Pattern

`SystemCapabilityDetector.checkBluetoothCapabilities()` creates two managers with `delegate: nil`:

```swift
self.centralManager  = CBCentralManager(delegate: nil, queue: nil)
self.peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)

DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    let available = self.centralManager?.state == .poweredOn  // May still be .unknown
    ...
}
```

**Why this is wrong:**

1. Without a delegate, `CBManagerStateDidChange` notifications are never delivered. The managers rely
   entirely on a synchronously available cached state — which is `.unknown` immediately after init.
2. The 1.0-second heuristic has no guarantee. On a system where `bluetoothd` is slow or restarting,
   the state is still `.unknown` at t=1.0s. The tool exits with "Bluetooth is not available."
3. Creating a `CBPeripheralManager(delegate: nil)` can trigger the macOS Bluetooth TCC permission
   dialog before the real strategy is ready to handle the response. If the user grants permission
   during this window, the subsequent `CBPeripheralManager(delegate: self)` in `startEmission()`
   may still see `.notDetermined` momentarily.
4. It is architecturally redundant: `peripheralManagerDidUpdateState` in the real strategy already
   handles `.poweredOff`, `.unauthorized`, `.unsupported`, and `.unknown` correctly.

**The correct pattern (standard CoreBluetooth):**

Create ONE `CBPeripheralManager` with a real delegate. Let `peripheralManagerDidUpdateState` be the
single source of truth for all state decisions. No pre-flight managers needed.

### 2.2 `EnhancediBeaconStrategy` Is Dead Code

The project's `LSMinimumSystemVersion` is `11.0`. `EnhancediBeaconStrategy` is selected only when
`restrictionsDetected == false`, which means `osVersion.majorVersion < 11`. This branch is
**unreachable on any supported device.** The class exists but never runs.

### 2.3 `PrivateKeyIBeaconStrategy`: Correct Approach, Wrong Verification

`PrivateKeyIBeaconStrategy` is the right idea — `kCBAdvDataAppleBeaconKey` is the same key used by
`CLBeaconRegion.peripheralData(withMeasuredPower:)` on iOS. When built via Xcode Archive, this key
causes `bluetoothd` to emit a true iBeacon frame OTA.

The problem is: `peripheralManagerDidStartAdvertising(error:)` always returns `error == nil` regardless
of whether the frame is emitted OTA or silently dropped by `bluetoothd`. CoreBluetooth only confirms
that the advertisement was *accepted by the stack*, not that it was *transmitted over the air*.

Without a self-scan verification step, it is impossible to distinguish "broadcasting successfully"
from "accepted but silently dropped."

### 2.4 GATT Strategy: Works But Is Misrepresented

`GATTServiceStrategy` does actually emit a BLE advertisement with service UUID. It is the only
mode that reliably transmits something detectable right now (regardless of build method). However:

1. The initial `beaconServiceUUID` is hardcoded to the default UUID, not the config UUID.
   `setupGATTService()` reassigns `beaconServiceUUID` from config, but only after `startEmission`
   is called. This is fine at runtime but brittle.
2. The strategy is correctly labeled as non-iBeacon in output, but the CLI `--allow-gatt-fallback`
   UX makes it feel like an exception rather than the default working mode.

---

## 3. Redesigned Architecture

### 3.1 Guiding Principles

1. **One CBPeripheralManager, one delegate, one source of truth.** No pre-flight managers.
2. **Fail loudly, succeed only when verified.** Use a self-scan loop to confirm OTA emission.
3. **Remove dead code.** `EnhancediBeaconStrategy` and `SimulatedBeaconStrategy` serve no runtime purpose.
4. **Make the build-method restriction visible in the tool's output.** The user must know whether
   they are looking at CoreBluetooth acceptance or actual OTA emission.
5. **Two modes only:** `iBeacon` (requires Xcode Archive, uses `kCBAdvDataAppleBeaconKey`) and
   `GATT` (always works, not standard iBeacon). No version-gated cascade.

### 3.2 New Component Map

```
BLEBeaconTool/
  main.swift                    — CLI: Advertise / Scan / Status (minimal logic)
  BeaconEmitter.swift           — NEW: unified emitter, replaces all strategies
  BeaconVerifier.swift          — NEW: CBCentralManager scan to confirm OTA emission
  BeaconScanner.swift           — unchanged
  BeaconConfiguration.swift     — unchanged
  BeaconError.swift             — add .emissionUnverified case
  SystemStatusChecker.swift     — unchanged

  [DELETE] BeaconBroadcaster.swift        (EnhancediBeaconStrategy)
  [DELETE] PrivateKeyIBeaconStrategy.swift
  [DELETE] GATTServiceStrategy.swift      (SimulatedBeaconStrategy lives here too)
  [DELETE] BeaconEmissionStrategy.swift   (protocol + broken SystemCapabilityDetector)
```

### 3.3 `BeaconEmitter` — Unified Emitter

Replaces all three strategy files. Internally holds one `CBPeripheralManager` and drives a state
machine through the delegate. Exposes a single `startEmission(config:mode:)` async method.

```
BeaconEmitter
  ├─ mode: EmissionMode              (.iBeacon | .gatt)
  ├─ CBPeripheralManager             (created once, real delegate)
  ├─ State: idle → starting → active → failed
  └─ startEmission(config:mode:) async -> Result<Void, BeaconError>
       └─ peripheralManagerDidUpdateState
            ├─ .poweredOn    → buildPayload() → startAdvertising()
            ├─ .unauthorized → .failure(.bluetoothUnauthorized)
            ├─ .poweredOff   → .failure(.bluetoothPoweredOff)
            └─ .unsupported  → .failure(.bluetoothUnsupported)
       └─ peripheralManagerDidStartAdvertising(error:)
            ├─ error != nil  → .failure(.advertisingFailed)
            └─ error == nil  → .success (CBStack accepted — NOT yet OTA-confirmed)
```

#### EmissionMode enum

```swift
enum EmissionMode {
    case iBeacon   // kCBAdvDataAppleBeaconKey — true iBeacon if built via Xcode Archive
    case gatt      // CBAdvertisementDataServiceUUIDsKey — always works, not standard iBeacon
}
```

#### Payload construction (iBeacon mode)

21-byte payload passed to `kCBAdvDataAppleBeaconKey`. CoreBluetooth prepends `4C 00 02 15`.

```
[0..15]  UUID (big-endian, native byte order of UUID struct)
[16..17] Major (big-endian)
[18..19] Minor (big-endian)
[20]     TX Power (UInt8 bitPattern of Int8)
```

No changes needed here — `PrivateKeyIBeaconStrategy.buildPayload()` is correct.

### 3.4 `BeaconVerifier` — OTA Emission Confirmation

This is the missing piece. After `startEmission()` returns `.success`, `BeaconVerifier` uses a
`CBCentralManager` to scan for the beacon UUID and confirms whether the frame is actually on air.

```
BeaconVerifier
  ├─ CBCentralManager (with delegate)
  ├─ timeout: TimeInterval (default 5s)
  └─ verify(uuid: UUID, mode: EmissionMode) async -> VerificationResult

VerificationResult
  ├─ .confirmed(rssi: Int)          — beacon detected OTA
  ├─ .notDetected                   — nothing received within timeout
  └─ .scanUnavailable               — central manager not powered on
```

**How it works:**
- For `.iBeacon` mode: scan for manufacturer data with Apple Company ID `0x4C 00` and matching UUID
- For `.gatt` mode: scan for service UUID matching config UUID
- Runs for `timeout` seconds, then resolves

**What the output means:**
- `.confirmed` → emission is working (OTA verified)
- `.notDetected` → CBStack accepted but `bluetoothd` is dropping the frame (most likely cause: not
  built via Xcode Archive)

### 3.5 New `main.swift` Advertise Flow

```swift
func run() throws {
    let config = try BeaconConfiguration(...)

    // Default: iBeacon mode. Fall back to GATT only if explicitly requested.
    let mode: EmissionMode = allowGattFallback ? .gatt : .iBeacon

    let emitter = BeaconEmitter()
    signal(SIGINT, SIG_IGN)
    let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSrc.setEventHandler { Task { await emitter.stopEmission() }; exit(0) }
    sigintSrc.resume()

    Task {
        // 1. Start emission (handles BT state internally via delegate)
        let result = await emitter.startEmission(config: config, mode: mode)
        guard case .success = result else {
            // Print error from result
            exit(1)
        }

        print("CB stack accepted advertisement. Verifying OTA emission...")

        // 2. Self-verify OTA emission
        let verifier = BeaconVerifier(timeout: 5.0)
        let verification = await verifier.verify(uuid: config.uuid, mode: mode)

        switch verification {
        case .confirmed(let rssi):
            print("OTA CONFIRMED — beacon detected at RSSI \(rssi) dBm")
            print("Broadcasting. Press Ctrl+C to stop.")
        case .notDetected:
            print("WARNING: CBStack accepted but NO beacon detected OTA.")
            print("Cause: binary was not built via Xcode Archive (bluetoothd restriction).")
            print("Action: Build via Xcode IDE > Product > Archive to enable true iBeacon OTA.")
            if !allowGattFallback && !strictIBeacon {
                print("Tip: run with --allow-gatt-fallback for a GATT beacon that is always detectable.")
            }
            if strictIBeacon { exit(1) }
            // Continue running — the iBeacon key is accepted by CBStack at least
        case .scanUnavailable:
            print("INFO: Cannot self-verify (CBCentral not ready). Assuming broadcast is active.")
        }

        // 3. Status timer loop (RunLoop.main.run() is the keepalive)
    }

    RunLoop.main.run()
}
```

### 3.6 Removing `SystemCapabilityDetector`

Delete entirely. Its two responsibilities are now handled correctly:

| Old responsibility | New owner |
|---|---|
| Check BT available | `peripheralManagerDidUpdateState` in `BeaconEmitter` |
| Check BT authorized | `peripheralManagerDidUpdateState` (.unauthorized case) |
| Recommend strategy | `EmissionMode` from CLI flag (`--allow-gatt-fallback`) |

---

## 4. Implementation Plan

### Phase 1 — Immediate Code Fixes (low risk, isolated changes)

**Goal:** Stop the tool from exiting on pre-flight false negatives and eliminate dead code.
These changes can be done without the full redesign and improve reliability immediately.

| # | File | Change |
|---|---|---|
| 1.1 | `main.swift` | Remove `checkBluetoothCapabilities()` and `checkPermissions()` pre-flight calls (lines 89–104). Let `startEmission()` handle state. |
| 1.2 | `main.swift` | Remove `canEmit()` call for `EnhancediBeaconStrategy` (lines 119–122). Redundant and broken. |
| 1.3 | `main.swift` | Simplify strategy cascade: since min target is macOS 11.0, remove the `!capabilities.restrictionsDetected` branch entirely. Always use `PrivateKeyIBeaconStrategy` first. |
| 1.4 | `BeaconEmissionStrategy.swift` | Delete `SystemCapabilityDetector` class entirely. |
| 1.5 | `BeaconBroadcaster.swift` | Delete `EnhancediBeaconStrategy`. Keep only extensions (`CBManagerState.description`, `DateFormatter.timestamp`, `String.chunked`). Move extensions to a `Extensions.swift` file. |

After Phase 1, the flow is:
```
run() → PrivateKeyIBeaconStrategy.startEmission() → delegate handles all state
```
No pre-flight races. No false exits on first run.

---

### Phase 2 — Core Redesign (medium risk, new files)

**Goal:** Replace the three strategy files with `BeaconEmitter` + `BeaconVerifier`.

#### Step 2.1 — Create `BeaconEmitter.swift`

New file. Implements:
- `EmissionMode` enum (`.iBeacon`, `.gatt`)
- `BeaconEmitter: NSObject, CBPeripheralManagerDelegate`
  - `startEmission(config:mode:) async -> Result<Void, BeaconError>`
  - `stopEmission() async`
  - `isEmitting: Bool`
  - GATT setup (`CBMutableService`, `CBMutableCharacteristic`) moved from `GATTServiceStrategy`
  - iBeacon payload construction moved from `PrivateKeyIBeaconStrategy.buildPayload()`
  - Status timer (single implementation, no duplication)

#### Step 2.2 — Create `BeaconVerifier.swift`

New file. Implements:
- `VerificationResult` enum (`.confirmed(rssi:)`, `.notDetected`, `.scanUnavailable`)
- `BeaconVerifier: NSObject, CBCentralManagerDelegate`
  - `verify(uuid:mode:) async -> VerificationResult`
  - Scans for max `timeout` seconds
  - For `.iBeacon`: matches manufacturer data (`0x4C 00 02 15` + UUID)
  - For `.gatt`: matches service UUID advertisement

#### Step 2.3 — Update `main.swift`

Rewrite `Advertise.run()` to use new `BeaconEmitter` + `BeaconVerifier` per Section 3.5.
- `EmissionMode` derived from `--allow-gatt-fallback` flag
- Remove `--strict-ibeacon` flag OR redefine: if strict and `.notDetected`, exit(1)
- Status updates use a single `Timer` scheduled from `main.swift` (not inside the emitter)

#### Step 2.4 — Delete old strategy files

- `BeaconBroadcaster.swift` (after moving extensions)
- `PrivateKeyIBeaconStrategy.swift`
- `GATTServiceStrategy.swift`
- `BeaconEmissionStrategy.swift` (protocol no longer needed; `BeaconEmitter` is concrete)

#### Step 2.5 — Update `BeaconError.swift`

Add case:
```swift
case emissionUnverified  // CBStack accepted but OTA self-scan found nothing
```

---

### Phase 3 — Build Pipeline (non-code)

**Goal:** Make it impossible for the user to misinterpret a successful run as working OTA iBeacon
unless it was built via Xcode Archive.

| # | Action |
|---|---|
| 3.1 | At startup, print which build method was used (inspect Mach-O or use a compile-time flag). |
| 3.2 | `BeaconVerifier.notDetected` output explicitly states: "This is expected for xcodebuild/swift build. Use Xcode IDE > Product > Archive." |
| 3.3 | Add `ARCHIVE_BUILD=1` as a Swift compile flag set only in the Archive scheme. Read it at runtime: `#if ARCHIVE_BUILD`. Use to adjust output and verification timeout. |
| 3.4 | Document in README: the only supported workflow for true iBeacon OTA emission is Xcode Archive. |

---

## 5. File Change Summary

| File | Action | Phase |
|---|---|---|
| `main.swift` | Rewrite `Advertise.run()` | 1 + 2 |
| `BeaconEmitter.swift` | CREATE | 2 |
| `BeaconVerifier.swift` | CREATE | 2 |
| `Extensions.swift` | CREATE (move shared extensions here) | 2 |
| `BeaconError.swift` | Add `.emissionUnverified` | 2 |
| `BeaconConfiguration.swift` | No change | — |
| `BeaconScanner.swift` | No change | — |
| `SystemStatusChecker.swift` | No change | — |
| `BeaconBroadcaster.swift` | DELETE | 2 |
| `PrivateKeyIBeaconStrategy.swift` | DELETE | 2 |
| `GATTServiceStrategy.swift` | DELETE | 2 |
| `BeaconEmissionStrategy.swift` | DELETE | 1 |

---

## 6. Key Design Decisions and Rationale

### Why not keep the strategy protocol?

The `BeaconEmissionStrategy` protocol was designed for extensibility, but in practice there are only
two meaningful modes on macOS 11+ (iBeacon and GATT). A protocol adds indirection without benefit.
A single `BeaconEmitter` with an `EmissionMode` parameter is simpler, easier to read, and eliminates
the duplication of timer/status code across three classes.

### Why is `BeaconVerifier` separate from `BeaconEmitter`?

A `CBPeripheralManager` (peripheral role) and a `CBCentralManager` (central role) can coexist in
the same process on macOS. Keeping them in separate objects preserves single responsibility:
`BeaconEmitter` is always the peripheral, `BeaconVerifier` is always the central. Mixing them in
one class creates delegate method ambiguity.

### Why not use `CLLocationManager` for self-verification?

`CLLocationManager.startRangingBeacons()` requires iOS or a Mac Catalyst app. It is unavailable
in a macOS command-line tool. `CBCentralManager` scanning for raw manufacturer data is the correct
approach for a macOS CLI.

### Why remove the version gate (`macOS < 11` branch)?

`LSMinimumSystemVersion = 11.0`. The `EnhancediBeaconStrategy` path requires `macOS.majorVersion < 11`
to be selected, which is impossible. Keeping dead code increases maintenance surface and creates
confusion for future readers. Remove it.

### Why does `peripheralManagerDidStartAdvertising(error:)` return `nil` even when dropped?

This is a `bluetoothd` enforcement, not a CoreBluetooth API behavior. CoreBluetooth's role ends at
handing the advertisement data to `bluetoothd`. If `bluetoothd` accepts the handoff (which it always
does regardless of whether it will transmit), it returns success. The decision to drop the `0x4C`
frame happens at a lower layer inside `bluetoothd`, asynchronously, with no error propagation back
to CoreBluetooth. This is why self-verification via scan is the only reliable confirmation mechanism.

---

## 7. Expected Outcomes After Implementation

| Scenario | Before | After |
|---|---|---|
| First run (permissions not yet granted) | Exits with "Bluetooth access is not authorized" | Proceeds; TCC dialog appears; delegate handles grant/deny |
| macOS 11+ xcodebuild binary, iBeacon mode | Prints "Broadcasting!" (false success) | Prints "OTA NOT CONFIRMED — bluetoothd restriction. Use Xcode Archive." |
| Xcode Archive binary, iBeacon mode | Prints "Broadcasting!" (true but unverified) | Prints "OTA CONFIRMED — beacon detected at RSSI X dBm" |
| GATT mode (any build method) | Works but misrepresented | Works; clearly labeled as GATT, OTA-confirmed by self-scan |
| Bluetooth powered off | May exit during pre-flight with misleading message | Prints "Bluetooth is powered off" from delegate; clean exit |
