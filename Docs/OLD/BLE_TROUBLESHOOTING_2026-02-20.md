# BLE Beacon Tool - Troubleshooting Log (2026-02-20)

## Summary

Both `scan` and `advertise` commands appeared to succeed in the terminal but did not function. This document records the root causes found and fixes applied.

---

## Issue 1: Scanner Hangs at Initialization

### Symptom
```
🔄 Initializing Bluetooth Central Manager...
(hangs forever, no beacon detected)
```

### Root Cause: Main Thread Deadlock in `main.swift`

The `Scan` command was using `DispatchSemaphore.wait()` to block the main thread while waiting for the scan to finish:

```swift
scanner.startScanning()
let semaphore = DispatchSemaphore(value: 0)
DispatchQueue.main.asyncAfter(...) {
    scanner.stopScanning()
    semaphore.signal()
}
semaphore.wait()  // ← BLOCKS main thread
```

`CBCentralManager` delivers its delegate callbacks (`centralManagerDidUpdateState`) via the main run loop. Because `semaphore.wait()` blocked the main thread, the run loop could not advance, so the callback never fired — and initialization appeared to hang.

### Fix Applied (`main.swift`)
Replaced `semaphore.wait()` with `RunLoop.main.run()` to keep the main run loop alive:

```swift
scanner.startScanning()
DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(duration)) {
    scanner.stopScanning()
    Foundation.exit(0)
}
RunLoop.main.run()  // ← Keeps run loop alive; BLE callbacks delivered normally
```

### Result ✅
```
✅ Bluetooth powered on
🔍 Starting raw BLE beacon scan...
🎯 Scanning for all iBeacons
⏰ Scanning for 20 seconds...
--------------------------------------------------
[18:04:11] 📡 Found: 92821D61-9FEE-4003-87F1-31799E12017A
           Major: 0, Minor: 1143
           RSSI: -33 dBm, Proximity: Immediate (<1m)
```

---

## Issue 2: Scanner Used Wrong API (`CLLocationManager`)

### Symptom
Even with the run loop fix, the original `BeaconScanner` used `CLLocationManager.startRangingBeacons`, which requires Location Services permission on macOS. Command-line apps and even App Bundles frequently fail to trigger this prompt, causing the scanner to silently find no beacons.

### Fix Applied (`BeaconScanner.swift`)
Completely replaced `CLLocationManager` with `CBCentralManager` to scan raw BLE advertisement packets and manually decode the iBeacon manufacturer data (`0x4C000215` prefix). This requires only Bluetooth permission, not Location Services.

### Verification
Before fixing, a test script (`test_scanner.swift`) using `CBCentralManager` directly detected **109 iBeacon packets** from the user's iPhone in 30 seconds — confirming the Mac hardware can hear the signal and the issue was purely the wrong API.

---

## Issue 3: Advertise Does Not Emit Real iBeacons

### Symptom
Advertise reports success but no real iBeacon is visible to other devices.

### Root Cause: macOS CoreBluetooth Restriction
On macOS, `CBPeripheralManager` **silently strips** the `CBAdvertisementDataManufacturerDataKey` (the actual iBeacon payload) when `startAdvertising` is called. The advertisement goes out, but without the Apple Company ID + iBeacon type bytes — so it is not a valid iBeacon. No error is returned, making it appear successful.

### Decision
This is a macOS OS-level restriction and cannot be bypassed via public APIs. The tool is now focused on **scanning only**. Use an iPhone or hardware beacon device to broadcast iBeacons.

---

## Current Working Commands

```bash
# Scan for all iBeacons (30 seconds)
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool scan --duration 30

# Scan filtering by UUID
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool scan \
    --uuid 92821D61-9FEE-4003-87F1-31799E12017A \
    --duration 30

# Verbose scan (shows raw hex payload + peripheral ID)
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool scan --verbose --duration 30

# Rebuild & repackage after code changes
xcodebuild -project BLEBeaconTool.xcodeproj -scheme BLEBeaconTool -configuration Release build
cp ~/Library/Developer/Xcode/DerivedData/BLEBeaconTool-*/Build/Products/Release/BLEBeaconTool ./ble-beacon-tool
./package_app.sh
```

---

## System Info
- **Device**: Mac Mini M4 Pro (Mac16,11)
- **macOS**: 15.7.3 (Build 24G419)
- **Bluetooth**: BCM_4388C2 — functional for scanning
