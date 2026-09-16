# Implementation Plan - Fixing BLE Scan and Advertise on macOS

## Problem Discovery

You mentioned that "scan does not work" and "advertise does not work" even though the terminal says success. Here is exactly why this happens on macOS:

1. **Why Scan Fails**:
   The current `BeaconScanner` uses `CLLocationManager.startRangingBeacons`. On macOS, this strictly requires Location Services permission ("Allow when using the app"). Command-line applications (even when packaged as an App Bundle) frequently fail to trigger this prompt or are silently denied by the system, causing the scanner to silently find nothing.
   
   **Verification**: I just wrote and ran a test script using `CBCentralManager` (raw Bluetooth scanning) while your iPhone was emitting. **It successfully caught your iPhone's iBeacon (UUID: 92821D61..., Major: 0, Minor: 1143)**! This proves that the Mac *can* hear the beacon, but `CLLocationManager` is blocking the app from seeing it due to location privacy restrictions.

2. **Why Advertise Fails**: 
   The `EnhancediBeaconStrategy` attempts to broadcast an iBeacon by passing `CBAdvertisementDataManufacturerDataKey` to `CBPeripheralManager`. 
   **Apple restricts this on macOS.** `CBPeripheralManager` silently strips the manufacturer data (the actual iBeacon payload) and only broadcasts the `LocalName`. Because `startAdvertising` doesn't throw an error, the terminal reports success, but no actual iBeacon signal is emitted over the air.

## Proposed Solutions

### 1. Fix the Scanner (Confirmed Working)
I will completely rewrite `BeaconScanner.swift` to stop using `CLLocationManager` and instead use `CBCentralManager`. 
- **How it works**: It will sniff raw BLE advertisement packets, manually decode the Apple Manufacturer Data (`0x4C000215`), and extract the UUID, Major, Minor, and RSSI.
- **Benefit**: This bypasses macOS Location Services entirely. It uses pure Bluetooth and will reliably detect your iPhone's beacons (as we just proved).

### 2. Handle the Broadcaster Limitation
Since macOS strictly forbids broadcasting standard iBeacons via public CoreBluetooth APIs, we must decide how you want to handle the broadcaster:

- **Option A (Deprecate)**: Leave the Broadcaster feature as-is with a warning that it doesn't emit true iBeacons due to macOS limitations. Rely on your iPhone to do the broadcasting, and use the Mac exclusively as a reliable scanner.
- **Option B (Mac-to-Mac Simulation via GATT)**: Modify the tool to use `GATTServiceStrategy.swift` instead. The Mac broadcasts a standard BLE CoreBluetooth GATT service containing the beacon data. The new scanner will be updated to look for *both* real iBeacons (from iPhones) and GATT beacons (from other Macs). *Note: iOS apps looking strictly for iBeacons won't see this Mac GATT beacon.*

## User Review Required

> [!IMPORTANT]
> The test successfully proved we can fix the scanner. I am ready to implement the `CBCentralManager` rewrite for `BeaconScanner.swift`. 

Please let me know:
1. **Shall I proceed with fixing the scanner?**
2. **For the broadcaster restriction, do you prefer Option A (Scanner-focused tool) or Option B (Add Mac-to-Mac GATT simulation)?**
