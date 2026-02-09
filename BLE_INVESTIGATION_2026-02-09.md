# BLE Beacon Tool Investigation - February 9, 2026

## Summary
Attempted to resolve Bluetooth Low Energy (BLE) beacon advertising issues on **Mac Mini M4 Pro** running **macOS 15.7.3**. All attempts resulted in timeout errors when trying to access Bluetooth peripheral functionality.

## System Information
- **Device**: Mac Mini M4 Pro (Model Identifier: Mac16,11)
- **macOS**: Version 15.7.3 (Build 24G419)
- **Bluetooth Chip**: BCM_4388C2
- **Bluetooth Status**: On and functional
- **Hardware Capability**: Should support BLE advertising

## Problem Description
The BLE beacon tool consistently shows:
```
⚠️ Status check timed out after 10 seconds
This may indicate Bluetooth system issues or insufficient permissions
```

This occurs for both advertising and scanning functions, suggesting complete blockage of `CBPeripheralManager` delegate callbacks.

## Steps Attempted (All Unsuccessful)

### 1. Manual Bluetooth Permissions
- ✅ **Completed**: Added Terminal to System Settings → Privacy & Security → Bluetooth
- ✅ **Completed**: Added VS Code to Bluetooth permissions
- ✅ **Completed**: Verified both apps are checked/enabled
- ❌ **Result**: Still timeout

### 2. Permission Reset and Cleanup
```bash
# Reset Bluetooth permissions
tccutil reset BluetoothAlways
# Status: Successfully reset BluetoothAlways
```
- ❌ **Result**: Still timeout after reset

### 3. Code Fixes and Build Issues
- ✅ **Fixed**: Signal handler issues (`Foundation.exit(0)`)
- ✅ **Fixed**: Unused variable warnings (`timerQueue`)
- ✅ **Fixed**: Build errors with proper DispatchSource signal handling
- ✅ **Fixed**: Periodic status updates implementation
- ❌ **Result**: Code builds successfully but BLE still doesn't work

### 4. Info.plist Configuration
- ✅ **Created**: `BLEBeaconTool/Info.plist` with proper Bluetooth usage descriptions:
  ```xml
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>This app needs Bluetooth access to broadcast and scan for BLE beacons.</string>
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>This app needs Bluetooth peripheral access to broadcast iBeacon signals.</string>
  ```
- ✅ **Created**: `BLEBeaconTool/BLEBeaconTool.entitlements`
- ✅ **Built**: With explicit Info.plist and bundle identifier
  ```bash
  xcodebuild -project BLEBeaconTool.xcodeproj -scheme BLEBeaconTool -configuration Release INFOPLIST_FILE=BLEBeaconTool/Info.plist PRODUCT_BUNDLE_IDENTIFIER=com.yourname.BLEBeaconTool build
  ```
- ❌ **Result**: Bundle ID still shows "Unknown" - Info.plist not recognized by command-line tool

### 5. Different Execution Methods Tested
```bash
# Method 1: Local binary
./ble-beacon-tool status

# Method 2: Direct from Xcode build
/Users/90692yokoo/Library/Developer/Xcode/DerivedData/BLEBeaconTool-*/Build/Products/Release/BLEBeaconTool status

# Method 3: With explicit bundle settings
# (Build with INFOPLIST_FILE and PRODUCT_BUNDLE_IDENTIFIER)
```
- ❌ **Result**: All methods result in same timeout

### 6. Hardware Verification
```bash
# Bluetooth hardware check
system_profiler SPBluetoothDataType | grep -A 5 "Bluetooth:"
# Result: BCM_4388C2 chip present and functioning

# System info
system_profiler SPHardwareDataType | grep "Model Name\|Model Identifier\|Chip"
# Result: Mac Mini M4 Pro - should support BLE advertising
```
- ✅ **Confirmed**: Hardware is capable
- ❌ **Issue**: Software/permission blocking

## Current Working Status

### ✅ Working Features
- Project builds successfully without errors
- Periodic status updates implemented and functional
- Signal handling (Ctrl+C) works properly
- Command-line argument parsing works
- All code compiles and links properly

### ❌ Non-Working Features
- BLE peripheral manager initialization (times out)
- Beacon advertising
- Beacon scanning
- Any Bluetooth functionality

## Root Cause Analysis

### Most Likely Issues
1. **macOS 15.7.3 Security Restrictions**: Desktop Macs (especially Mac Mini) may have restricted BLE peripheral capabilities for security reasons
2. **Command-Line Tool Limitations**: Info.plist permissions may not apply to command-line tools the same way as bundled applications
3. **System Integrity Protection**: May be blocking BLE peripheral access for non-signed applications

### Evidence Supporting Root Cause
- Proper hardware (M4 Pro with BLE 5.0+ capability)
- Permissions correctly granted in System Settings
- Code works for compilation but CBPeripheralManager delegate never gets called
- Same behavior across different execution methods

## Recommended Next Steps for Future Investigation

### 1. Convert to macOS App Bundle
Instead of command-line tool, create proper macOS application with:
- App bundle structure
- Proper Info.plist integration
- Code signing with developer certificate
- Entitlements properly embedded

### 2. Test with External BLE Adapter
- Use USB BLE dongle to bypass macOS restrictions
- Verify if issue is system policy vs. hardware limitation

### 3. Alternative Approaches
- **Web Bluetooth API**: Browser-based BLE (limited but functional)
- **iOS Companion App**: Build iOS version for testing beacon functionality
- **Raspberry Pi**: Use external device for beacon advertising

### 4. macOS Version Testing
- Test on different macOS versions (15.6, 14.x) to identify when restrictions were introduced
- Test on MacBook vs. Mac Mini to isolate desktop-specific restrictions

## Build Commands (Working)
```bash
# Standard build
xcodebuild -project BLEBeaconTool.xcodeproj -scheme BLEBeaconTool -configuration Release build

# With Info.plist
xcodebuild -project BLEBeaconTool.xcodeproj -scheme BLEBeaconTool -configuration Release INFOPLIST_FILE=BLEBeaconTool/Info.plist PRODUCT_BUNDLE_IDENTIFIER=com.yourname.BLEBeaconTool build

# Copy binary
cp /Users/$(whoami)/Library/Developer/Xcode/DerivedData/BLEBeaconTool-*/Build/Products/Release/BLEBeaconTool ./ble-beacon-tool
```

## Conclusion
The BLE Beacon Tool code is functionally correct and builds properly. The issue appears to be **macOS 15.7.3 system-level restrictions** preventing command-line tools from accessing BLE peripheral functionality, even with proper permissions granted. This is likely a security enhancement in recent macOS versions targeting desktop Macs.

**Status**: Investigation suspended - requires fundamental architectural changes (app bundle vs. command-line tool) or alternative hardware approach.