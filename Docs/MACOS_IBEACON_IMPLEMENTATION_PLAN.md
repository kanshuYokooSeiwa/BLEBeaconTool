# macOS iBeacon Emission Fix Plan

## Goal Description

The CLI tool currently fails to emit a true iBeacon frame on macOS 11+, silently dropping the `kCBAdvDataAppleBeaconKey` payload, or failing completely with `CBAdvertisementDataManufacturerDataKey`.

By analyzing the working open-source `BeaconEmitter` application, we found that its payload construction is identical to our `PrivateKeyIBeaconStrategy`. However, there are systemic differences between a compiled GUI application and a command-line tool.

The goal is to align our CLI tool's environment with the working GUI app to successfully broadcast an iBeacon frame.

## Proposed Changes

We will attempt the following layered fixes.

### 1. Entitlements and Info.plist Alignment
The CLI tool might be silently restricted by macOS Bluetooth privacy features. 
- [MODIFY] `BLEBeaconTool/BLEBeaconTool.entitlements`
  - Ensure Bluetooth capability is present.
  - Test adding App Sandbox (`com.apple.security.app-sandbox`) if necessary, though CLI tools usually don't need it.
- [MODIFY] `BLEBeaconTool/Info.plist`
  - Ensure all required Bluetooth privacy strings are present (`NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`).

### 2. RunLoop and Execution Context
Command-line tools on macOS can terminate early or fail to dispatch delegate callbacks correctly if the main RunLoop isn't running properly.
- [MODIFY] `BLEBeaconTool/main.swift`
  - Ensure `RunLoop.main.run()` is keeping the process alive and servicing Bluetooth XPC callbacks correctly during advertising. The current implementation uses async/await, which usually manages this, but explicit RunLoop management might be required for `CBPeripheralManager` to function fully in a CLI.

### 3. Verification of `kCBAdvDataAppleBeaconKey`
Since `BeaconEmitter` successfully uses the 21-byte `kCBAdvDataAppleBeaconKey` payload, we will keep `PrivateKeyIBeaconStrategy.swift` as the primary method for macOS 11+.

## Verification Plan

### Automated Tests
*No automated unit tests apply directly to over-the-air BLE broadcasting.*

### Manual Verification
1. **Compile the updated CLI tool.**
2. **Execute the broadcast command:**
   ```bash
   ./ble-beacon-tool advertise --uuid "92821D61-9FEE-4003-87F1-31799E12017A" --major 0 --minor 1100
   ```
3. **Verify with nRF Connect (iPhone):**
   - Open nRF Connect on an iPhone.
   - Scan for peripherals.
   - Find the Mac's broadcast and check the **Advertising Data**.
   - **Success Condition:** The Manufacturer Data specifically shows the `4C 00 02 15` prefix followed by the UUID.
4. **Verify with iOS `CLLocationManager` (iPhone):**
   - Run a basic iOS app using `CLLocationManager.startRangingBeacons`.
   - **Success Condition:** The iOS app detects the beacon and provides proximity updates (Immediate/Near/Far).

## User Review Required
Please review this plan. The primary hypothesis is that macOS silently drops the payload in CLI tools lacking specific entitlements, plist configurations, or proper RunLoop lifecycle management, compared to standard AppKit apps.
