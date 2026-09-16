# Implementation Plan - Package BLEBeaconTool as App Bundle

## Problem
The `BLEBeaconTool` is a command-line tool that fails to broadcast or scan for beacons because macOS 15+ restricts Bluetooth access for standalone binaries that do not have a valid `Info.plist` with usage descriptions (`NSBluetoothAlwaysUsageDescription`, etc.) recognized by the privacy system (TCC).

## Solution
Package the existing binary into a proper macOS App Bundle (`.app`) structure. This allows macOS to correctly associate the `Info.plist` with the executable, enabling the permission prompts and access.

## Proposed Changes

### 1. Create App Bundle Structure
I will create a script `package_app.sh` to generate the following structure:
```
BLEBeaconTool.app/
└── Contents/
    ├── Info.plist
    └── MacOS/
        └── BLEBeaconTool
```

### 2. Configure `Info.plist`
Ensure `Info.plist` contains the necessary keys:
- `CFBundleIdentifier`: `com.k-yokoo.BLEBeaconTool`
- `CFBundleExecutable`: `BLEBeaconTool`
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`
- `NSLocationWhenInUseUsageDescription` (needed for scanning)

### 3. Code Signing
The script will also sign the app bundle using `codesign` with the existing entitlements file (`BLEBeaconTool.entitlements`) and the user's identity (or ad-hoc if no identity is available, though the previous investigation showed a valid identity `Apple Development: sc-kanshuuyokoo@docomo.ne.jp`).

## Verification Plan

### Automated Verification
- Run `codesign -dvvv BLEBeaconTool.app` to verify the signature and valid Info.plist.
- Run `spctl --assess --type execute --verbose --ignore-cache --no-cache BLEBeaconTool.app` to check assessment (optional, might fail for self-signed but good to check).

### Manual Verification
1.  Run the packaged tool:
    ```bash
    ./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool status
    ```
2.  Trigger Advertising:
    ```bash
    ./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool advertise
    ```
    - Check if "Bluetooth access unauthorized" error is gone.
    - Check if the system prompts for Bluetooth permission (if not already granted).
3.  Trigger Scanning:
    ```bash
    ./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool scan
    ```
    - Check if Location permission prompt appears (or "Location permission denied" error is gone).

### Script
I will provide `package_app.sh` to automate this process.
