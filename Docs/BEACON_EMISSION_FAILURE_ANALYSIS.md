# BLE Beacon Emission Failure Analysis

**Date:** 2026-04-27
**Status:** Root cause identified — multiple layers of failure, from OS restrictions to code bugs

---

## Executive Summary

The tool never successfully emits a detectable iBeacon signal due to a combination of one fundamental macOS system restriction and several code-level bugs. Even when the code appears to run without error, the beacon frame is silently discarded by the OS before it reaches the radio.

---

## Issue 1 — [CRITICAL / System Level] macOS 11+ Silently Drops Apple `0x4C` Frames

**Root cause of failure. This alone prevents true iBeacon emission regardless of code correctness.**

On macOS 11 and later, `bluetoothd` silently strips any BLE advertisement that contains Apple's reserved company ID (`0x4C 00`) manufacturer data unless the calling binary was produced by the **Xcode IDE's Archive export workflow** (`Product > Archive`). This is not documented by Apple.

### What happens in this codebase

- `EnhancediBeaconStrategy` (used on macOS < 11): uses `CBAdvertisementDataManufacturerDataKey` with the `0x4C 00` prefix — would be silently dropped on modern macOS anyway.
- `PrivateKeyIBeaconStrategy` (used on macOS 11+): uses `kCBAdvDataAppleBeaconKey` — CoreBluetooth reports `error == nil` (accepted), but `bluetoothd` still silently drops the `0x4C` frame over the air.
- GATT fallback: actually transmits, but is **not** a standard iBeacon and cannot be detected by iOS `CLLocationManager.startRangingBeacons()`.

### Build method vs. outcome (verified by prior investigation)

| Build Method | Outcome |
|---|---|
| `swift build` / `swift run` | Silently dropped |
| `xcodebuild` CLI | Silently dropped |
| Shell-packaged `.app` + codesign | Silently dropped |
| **Xcode IDE → Product → Archive** | **True iBeacon transmitted** |

Entitlements, codesign identity, Info.plist, and Team ID were confirmed identical between working and failing builds. The restriction is enforced at the `bluetoothd` layer based on metadata only the Xcode Archive pipeline injects (likely an embedded provisioning profile or Mach-O load command flag).

**Fix:** Build exclusively via **Xcode IDE > Product > Archive**. There is no known CLI workaround.

---

## Issue 2 — [HIGH / Code Bug] Permission Check Exits Before Permission Dialog Appears

**File:** `BLEBeaconTool/BeaconEmissionStrategy.swift:74`

```swift
func checkPermissions() async -> PermissionStatus {
    return PermissionStatus(
        bluetoothAuthorized: CBPeripheralManager.authorization == .allowedAlways,
        ...
    )
}
```

`CBPeripheralManager.authorization` returns `.notDetermined` on first launch (before the user has seen the Bluetooth permission dialog). The comparison `== .allowedAlways` returns `false`, so `main.swift:97` evaluates `!permissions.bluetoothAuthorized` as `true` and calls `Foundation.exit(1)` with "Bluetooth access is not authorized."

The actual Bluetooth permission dialog is only triggered when a `CBPeripheralManager` with a delegate is initialized — which happens later in `startEmission()`. **The app exits before that initialization ever occurs**, so the user never sees the permission prompt and can never grant access.

This means on a fresh install or after resetting permissions, the tool always exits immediately with a misleading error.

**Fix:** Treat `.notDetermined` as "possibly authorized — proceed and let CoreBluetooth request permission." Only hard-exit on `.denied` or `.restricted`.

---

## Issue 3 — [MEDIUM / Code Bug] `--allow-gatt-fallback` Flag Is Dead Code

**File:** `BLEBeaconTool/main.swift:38-39, 152-182`

The `allowGattFallback` flag is declared:

```swift
@Flag(help: "Allow fallback to GATT mode when iBeacon advertising is restricted on macOS")
var allowGattFallback = false
```

But it is **never read** in the `run()` function. The GATT fallback occurs unconditionally whenever `PrivateKeyIBeaconStrategy` fails (lines 162–182), regardless of whether the user passed `--allow-gatt-fallback` or not.

The only flag that actually changes behavior is `--strict-ibeacon` (which suppresses the fallback). This makes the CLI's help text misleading — users are told they need to explicitly allow the fallback, but it always happens.

---

## Issue 4 — [MEDIUM / Code Bug] Unreliable Bluetooth State Check in `checkBluetoothCapabilities()`

**File:** `BLEBeaconTool/BeaconEmissionStrategy.swift:51-71`

```swift
func checkBluetoothCapabilities() async -> SystemCapabilities {
    return await withCheckedContinuation { continuation in
        let centralManager = CBCentralManager(delegate: nil, queue: nil)
        let peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let capabilities = SystemCapabilities(
                bluetoothAvailable: centralManager.state == .poweredOn,
                ...
            )
            continuation.resume(returning: capabilities)
        }
    }
}
```

Both managers are created with `delegate: nil`. Without a delegate, state-change notifications cannot be received — the managers rely solely on their initial state value, which is `.unknown` immediately after creation. The fixed 0.5-second delay is a heuristic and is not reliable; on a slow or busy system the state may still be `.unknown` when sampled, causing `bluetoothAvailable` to return `false` even when Bluetooth is on.

Additionally, creating a `CBPeripheralManager` here (as a pre-flight check) may trigger the macOS Bluetooth permission dialog prematurely and unpredictably before the actual `startEmission()` call.

---

## Issue 5 — [MINOR / Code Bug] Duplicate Status Output in `BeaconBroadcaster`

**File:** `BLEBeaconTool/BeaconBroadcaster.swift:204-218`

```swift
private func startPeriodicStatusUpdates() {
    statusTimer = Timer.scheduledTimer(withTimeInterval: statusUpdateInterval, repeats: true) { _ in
        DispatchQueue.main.async { self.showStatus() }
    }
    RunLoop.current.add(statusTimer!, forMode: .common)

    // Also show initial status after first interval
    DispatchQueue.main.asyncAfter(deadline: .now() + statusUpdateInterval) {
        self.showStatus()
    }
}
```

The repeating timer fires at `t = 2s, 4s, 6s, ...`. The `asyncAfter` also fires at `t = 2s`. Both trigger `showStatus()` at the same moment, causing the first status line to be printed twice. `GATTServiceStrategy.swift:223-237` contains the same pattern.

---

## Issue 6 — [Design / Fundamental] GATT Fallback Is Not a Standard iBeacon

This is documented behavior, but worth restating clearly: when the tool falls back to `GATTServiceStrategy`, it advertises a custom GATT service using the beacon UUID as the service UUID. This is **not** the iBeacon format (Apple `0x4C 00 02 15` manufacturer data). Devices ranging iBeacons via `CLLocationManager` on iOS will never detect it. Only a `CBCentralManager` scanning for the specific service UUID will find it.

If the purpose of this tool is to emit iBeacons detectable by iOS apps using `CLLocationManager`, the GATT fallback does not fulfill that purpose.

---

## Summary Table

| # | Severity | Layer | Issue | Impact |
|---|---|---|---|---|
| 1 | Critical | OS / System | `bluetoothd` silently drops `0x4C` frames unless built via Xcode Archive | True iBeacon never transmitted on macOS 11+ |
| 2 | High | Code | Permission check exits on `.notDetermined` before dialog appears | Tool always exits on first run / after permission reset |
| 3 | Medium | Code | `--allow-gatt-fallback` flag is never read; fallback is always automatic | CLI flag is misleading / non-functional |
| 4 | Medium | Code | BT state check uses `delegate: nil` managers with fixed 0.5s delay | Unreliable capability detection |
| 5 | Minor | Code | Repeating timer + `asyncAfter` both fire at same interval | Duplicate status lines at first tick |
| 6 | Design | Architecture | GATT fallback is not a standard iBeacon format | Cannot be detected by iOS `CLLocationManager` |

---

## Recommended Next Steps

1. **For true iBeacon emission:** Build and export exclusively via **Xcode IDE > Product > Archive**. All CLI build methods are blocked at the `bluetoothd` level.
2. **Fix Issue 2:** Change the permission check to allow `.notDetermined` to proceed; only block on `.denied` or `.restricted`.
3. **Fix Issue 3:** Either read the `allowGattFallback` flag before falling back, or remove the flag and update help text to reflect that fallback is always automatic.
4. **Fix Issue 4:** Use a `CBPeripheralManager` with a proper delegate and wait for the `peripheralManagerDidUpdateState` callback rather than a fixed timer.
5. **Fix Issue 5:** Remove the redundant `asyncAfter` call in `startPeriodicStatusUpdates()`.
