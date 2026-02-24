# macOS True iBeacon Advertising — Issue Wrap-Up

**Date:** 2026-02-24  
**Status:** Workaround in place; fundamental limitation unresolved  
**Severity:** High — blocks iOS `CLLocationManager`-based detection entirely

---

## 1. Problem Statement

The goal of this tool is to let a macOS machine advertise as an iBeacon so that an iOS app using `CLLocationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint)` can detect and range it.

**This is currently impossible on macOS.**

macOS CoreBluetooth (`CBPeripheralManager`) silently drops `CBAdvertisementDataManufacturerDataKey` from any call to `startAdvertising(_:)`. The manufacturer-specific data payload — which is where the iBeacon type byte (`0x02`), Apple Company ID (`0x4C 0x00`), UUID, Major, Minor, and TxPower live — is never emitted over the air. The OS provides no error; `peripheralManagerDidStartAdvertising(_:error:)` fires with `error == nil`, making the failure completely silent.

---

## 2. Root Cause Analysis

### 2.1 iBeacon Wire Format

A true iBeacon advertisement consists of a BLE **AD Type 0xFF (Manufacturer Specific Data)** structure:

```
[Length] [0xFF] [0x4C] [0x00] [0x02] [0x15]
[UUID: 16 bytes] [Major: 2 bytes] [Minor: 2 bytes] [TxPower: 1 byte]
```

Total payload: 30 bytes inside the manufacturer data AD structure.

The `0x4C 0x00` is Apple's Bluetooth SIG-registered Company ID (little-endian). The `0x02 0x15` subtype identifies iBeacon specifically.

### 2.2 Why macOS Blocks It

macOS CoreBluetooth enforces a restriction on **custom manufacturer data** in peripheral advertisements starting with macOS Big Sur (11.0). The restriction appears to be an intentional API gap rather than a security policy:

- **iOS** exposes `CLBeaconRegion.peripheralData(withMeasuredPower:)` which returns a correctly configured dictionary that `CBPeripheralManager` accepts and emits verbatim as a true iBeacon frame.
- **macOS** has **no equivalent** of `CLBeaconRegion.peripheralData(withMeasuredPower:)` — `CoreLocation` framework is available on macOS but `CLBeaconRegion.peripheralData(withMeasuredPower:)` is **not** bridged to macOS.
- Passing a manually constructed `CBAdvertisementDataManufacturerDataKey` value to `startAdvertising` is silently ignored on macOS.

### 2.3 Verification

The codebase detects this restriction at runtime:

```swift
// BLEBeaconTool/BeaconEmissionStrategy.swift
private func detectmacOSRestrictions(_ version: OperatingSystemVersion) -> Bool {
    return version.majorVersion >= 11
}
```

This check correctly identifies macOS 11.0+ as restricted and routes the advertiser to the GATT fallback path automatically.

---

## 3. Current Workaround: GATT Fallback

A `GATTServiceStrategy` was implemented and is now the **default** advertise path on macOS.

### What it does

- Creates a `CBPeripheralManager` advertising a **custom GATT service** with a UUID derived from the beacon's UUID parameter.
- Service UUID: `<configured-uuid>` (e.g., `92821D61-9FEE-4003-87F1-31799E12017A`)
- Characteristic UUID: `<configured-uuid-with-B-suffix>` (e.g., `92821D61-9FEE-4003-87F1-31799E12017B`, read-only, dynamic value)
- The characteristic value encodes Major, Minor, TxPower as raw bytes, readable by connecting peripherals.
- Emits periodic 2-second status logs confirming active state.

### What it CANNOT do

| Capability | iBeacon (true) | GATT Fallback |
|---|---|---|
| Detected by `CLLocationManager.startRangingBeacons` | ✅ | ❌ |
| Detected by `CBCentralManager.scanForPeripherals` | ❌ | ✅ |
| Proximity ranging (Immediate/Near/Far) | ✅ | ❌ |
| Works without iOS app code changes | ✅ | ❌ |
| Emittable from macOS | ❌ | ✅ |

The GATT fallback is **useful for BLE connectivity testing** but does **not** satisfy the original requirement of being detected by `CLLocationManager`.

---

## 4. iOS App Compatibility Problem

The user's iOS app uses:

```swift
locationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
```

`CLLocationManager` only detects **manufacturer-specific AD frames with the iBeacon signature** (`0x4C 0x00 0x02 0x15 ...`). It does not scan for GATT services. These two APIs operate at fundamentally different layers:

| Layer | iBeacon (`CLLocationManager`) | GATT (`CBCentralManager`) |
|---|---|---|
| BLE Role | Observer (passive scan) | Central (active/passive) |
| Packet type matched | AD Type 0xFF, Apple Company ID | AD containing service UUID |
| Connection required | No | Optional (for GATT reads) |
| Power/distance model | TxPower-calibrated RSSI | Raw RSSI only |

There is no way to make `CLLocationManager` detect a GATT service advertisement without modifying the iOS app or changing the advertiser hardware/platform.

---

## 5. Attempted Dead Ends

### 5.1 Hardcoding `0x4C 0x00` bytes manually

The byte array for a valid iBeacon frame can be constructed in Swift:

```swift
var iBeaconBytes: [UInt8] = [
    0x4C, 0x00,        // Apple Company ID (little-endian)
    0x02, 0x15,        // iBeacon subtype + length
    // 16 UUID bytes
    // 2 Major bytes
    // 2 Minor bytes
    0xC5               // TxPower (-59 dBm)
]
let data = Data(iBeaconBytes)
peripheralManager.startAdvertising([
    CBAdvertisementDataManufacturerDataKey: data
])
```

**Result:** macOS accepts the call without error — but the manufacturer data is silently stripped from the over-the-air packet. The advertisement is emitted without the manufacturer-specific AD structure. The bytes never leave the machine.

### 5.2 Using `CBPeripheralManager` raw advertising slot

CoreBluetooth on macOS provides no "raw advertising" or "HCI bypass" API accessible from sandboxed apps.

### 5.3 `IOBluetooth` framework

Lower-level than CoreBluetooth but does not expose HCI advertising commands to user-space applications.

---

## 6. Known Viable Paths Forward

### Option A — Change iOS app to use `CBCentralManager`

**Effort:** Low (iOS code change only)  
**Hardware:** None required  
**Tradeoff:** Loses `CLLocationManager` proximity ranging (Immediate/Near/Far); must implement own RSSI-based distance estimation

```swift
// iOS replacement code
centralManager.scanForPeripherals(withServices: [CBUUID(string: "92821D61-9FEE-4003-87F1-31799E12017A")])

func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                    advertisementData: [String : Any], rssi RSSI: NSNumber) {
    // Use RSSI for distance estimation
    // Connect to peripheral and read characteristic for Major/Minor
}
```

The macOS tool already advertises the correct service UUID. No changes needed on the macOS side.

### Option B — Use Raspberry Pi (or any Linux) as iBeacon advertiser

**Effort:** Medium (shell script + BlueZ HCI commands)  
**Hardware:** Raspberry Pi, Linux machine, or USB Bluetooth dongle running Linux  
**Tradeoff:** Requires additional hardware; iOS app unchanged

BlueZ `hcitool` can emit raw HCI LE advertising commands with full manufacturer data:

```bash
# Set iBeacon advertising data (example — UUID/Major/Minor must be substituted)
sudo hcitool -i hci0 cmd 0x08 0x0008 1e 02 01 1a 1a ff 4c 00 02 15 \
  92 82 1d 61 9f ee 40 03 87 f1 31 79 9e 12 01 7a \  # UUID bytes
  00 00 04 4c c5 00                                    # Major 0 / Minor 1100 / TxPower -59
sudo hcitool -i hci0 cmd 0x08 0x000a 01               # Enable advertising
```

This emits a byte-perfect iBeacon frame detectable by `CLLocationManager` on iOS.

### Option C — Both A and B

Implement GATT scan path in iOS (`CBCentralManager`) for development/macOS testing, and use Pi script for production/device integration tests. Both detection paths can coexist in the iOS app.

---

## 7. Current Codebase State

All code changes from this investigation are committed (pending final git commit):

| File | Change | Status |
|---|---|---|
| `BLEBeaconTool/BeaconEmissionStrategy.swift` | OS version restriction detection (integer comparison, `>= 11`) | ✅ Done |
| `BLEBeaconTool/GATTServiceStrategy.swift` | Dynamic read characteristic, config-derived service UUID, 2-second status timer | ✅ Done |
| `BLEBeaconTool/BeaconBroadcaster.swift` | Timer interval 2 seconds | ✅ Done |
| `BLEBeaconTool/BeaconError.swift` | Updated recovery suggestion text | ✅ Done |
| `BLEBeaconTool/BeaconScanner.swift` | GATT fallback detection via service UUIDs + overflow UUIDs + name heuristic | ✅ Done |
| `BLEBeaconTool/main.swift` | Auto-fallback default, `--strict-ibeacon` flag, deterministic exits | ✅ Done |
| `README.md` | Documented flags, macOS limitation, troubleshooting | ✅ Done |

**Build status:** `BUILD SUCCEEDED` (Release, arm64, macOS 15.5)  
**Binary:** `./ble-beacon-tool`

---

## 8. Open Questions for Deeper Planning

1. **iOS app ownership**: Is modifying the iOS app (`CLLocationManager` → `CBCentralManager`) within scope?
2. **Proximity ranging requirement**: Is the Immediate/Near/Far classification from `CLLocationManager` required, or is raw RSSI sufficient?
3. **Hardware availability**: Is a Raspberry Pi or Linux machine with Bluetooth available for the Pi-based emitter path?
4. **Multi-platform support**: Should this tool eventually support emitting true iBeacon on iOS/iPadOS as well (where `CLBeaconRegion.peripheralData(withMeasuredPower:)` is available)?
5. **Sandboxing constraints**: Is the iOS app distributed via App Store? (App Store sandboxing still permits `CBCentralManager` scanning.)
6. **Production vs. development use case**: Is the macOS tool a development/testing utility or a production beacon source?

---

## 9. References

- [Apple Developer — CLBeaconRegion.peripheralData(withMeasuredPower:)](https://developer.apple.com/documentation/corelocation/clbeaconregion/1621388-peripheraldata) — iOS/iPadOS only
- [Apple Developer — CBPeripheralManager.startAdvertising](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/1393252-startadvertising) — `CBAdvertisementDataManufacturerDataKey` silently ignored on macOS
- [Bluetooth SIG — Company Identifiers](https://www.bluetooth.com/specifications/assigned-numbers/) — Apple Inc. = `0x004C`
- [BlueZ hcitool iBeacon setup](https://github.com/custom-beacon-transmitter/ble-ibeacon) — Linux reference implementation
- iBeacon Specification: Bluetooth Core Specification v4.0+, AD Type `0xFF`, Company ID `0x004C`, subtype `0x02 0x15`
