# BLE Beacon Tool

A command-line tool for broadcasting and scanning Bluetooth Low Energy (BLE) iBeacon signals on macOS.

## Features

- 📡 **Broadcast iBeacon signals** with customizable UUID, Major, Minor, and TX Power
- 🔍 **Scan for nearby beacons** with filtering and detailed reporting
- 📊 **System status checking** and troubleshooting guidance
- 🎯 **Default test UUID** for quick testing: `92821D61-9FEE-4003-87F1-31799E12017A`

## Installation

### Option 1: Xcode Project
1. Open `BLEBeaconTool.xcodeproj` in Xcode
2. Build and run (⌘R)

### Option 2: Swift Package Manager
```bash
swift build -c release
cp .build/release/BLEBeaconTool /usr/local/bin/
```

## Usage

### Broadcast Beacon (Default)
```bash
# Basic usage with defaults (UUID: 92821D61-9FEE-4003-87F1-31799E12017A, Major: 100, Minor: 1)
./BLEBeaconTool

# Custom parameters
./BLEBeaconTool advertise --uuid "12345678-1234-1234-1234-123456789ABC" --major 200 --minor 5 --power -45

# Verbose output
./BLEBeaconTool advertise --verbose
```

### Typical Range by TX Power

TX Power (dBm) | Approximate Range | Use Case
---------------|-------------------|----------
+4 dBm         | ~100-150 meters   | Maximum range, high power
 0 dBm         | ~70-100 meters    | Long range applications  
-4 dBm         | ~50-70 meters     | Medium-long range
-8 dBm         | ~30-50 meters     | Medium range
-12 dBm        | ~20-30 meters     | Short-medium range
-16 dBm        | ~10-20 meters     | Short range
-20 dBm        | ~5-15 meters      | Very short range
-40 dBm        | ~1-5 meters       | Proximity only
-59 dBm        | ~0.5-2 meters     | Immediate proximity


### Scan for Beacons

The tool supports comprehensive beacon scanning with flexible filtering options:

#### Scan All Beacons (No UUID Filter)
```bash
# Scan for ALL iBeacons in range (discovery mode)
./BLEBeaconTool scan

# Scan all beacons for 2 minutes with verbose output
./BLEBeaconTool scan --duration 120 --verbose

# Quick 10-second scan of all nearby beacons
./BLEBeaconTool scan --duration 10
```

#### Scan Specific UUID
```bash
# Scan with specific UUID filter
./BLEBeaconTool scan --uuid "92821D61-9FEE-4003-87F1-31799E12017A"

# Filter by UUID with custom duration
./BLEBeaconTool scan --uuid "12345678-1234-1234-1234-123456789ABC" --duration 60
```

**Discovery Mode Benefits:**
- 🔍 **Find all nearby beacons** regardless of UUID
- 📊 **Survey beacon density** in your environment  
- 🐛 **Debug and troubleshoot** unknown beacons
- 🏢 **Audit existing beacon deployments**

### Check System Status
```bash
./BLEBeaconTool status
```

## Command Reference

| Command | Description | Parameters |
|---------|-------------|------------|
| `advertise` | Broadcast iBeacon signal | `--uuid`, `--major`, `--minor`, `--power`, `--verbose` |
| `scan` | Scan for beacons (all or filtered by UUID) | `--uuid` (optional), `--duration`, `--verbose` |
| `status` | Show system status | None |

## Parameters

- `--uuid` / `-u`: Beacon UUID (default: 92821D61-9FEE-4003-87F1-31799E12017A for advertising, optional for scanning)
- `--major` / `-m`: Major value 0-65535 (default: 100)
- `--minor` / `-n`: Minor value 0-65535 (default: 1)  
- `--power` / `-p`: TX Power -59 to 4 dBm (default: -59)
- `--duration` / `-d`: Scan duration in seconds (default: 30)
- `--verbose` / `-v`: Enable detailed output

## Permissions Required

### Bluetooth Access
1. **System Settings** → **Privacy & Security** → **Bluetooth**
2. Enable access for **Terminal** or your app

### Location Access (for scanning)
1. **System Settings** → **Privacy & Security** → **Location Services**
2. Enable access for **Terminal** or your app

## Output Examples

### Broadcasting
```
🎯 BLE iBeacon Broadcaster
UUID: 92821D61-9FEE-4003-87F1-31799E12017A
Major: 100, Minor: 1
TX Power: -59 dBm
==================================================
✅ Bluetooth powered on
✅ Broadcasting iBeacon successfully!
📡 Beacon ID: TestBeacon-100-1

[14:30:15] Status: 🟢 ACTIVE | UUID: 92821D61-9FEE-4003-87F1-31799E12017A | Major: 100 | Minor: 1
```

### Scanning
```
📡 BLE iBeacon Scanner
Scanning for all iBeacons
Duration: 30 seconds
==================================================
✅ Location permission granted
🔍 Starting beacon scan...
⏰ Scanning for 30 seconds...

[14:30:45] 📡 Found: 92821D61-9FEE-4003-87F1-31799E12017A
           Major: 100, Minor: 1
           RSSI: -45 dBm, Proximity: Near (1-3m)
           Accuracy: 2.15m

[14:30:48] 📡 Found: E2C56DB5-DFFB-48D2-B060-D0F5A71096E0
           Major: 1, Minor: 1
           RSSI: -62 dBm, Proximity: Far (>3m)
           Accuracy: 5.42m
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Bluetooth access unauthorized" | Grant Bluetooth permissions in System Settings |
| "Location permission denied" | Grant Location permissions for scanning features |
| No beacons detected | Check if beacon is broadcasting, verify UUID filter |
| Command not found | Ensure tool is in PATH or use full path |

## Testing Your iOS App

1. **Start broadcasting:**
   ```bash
   ./BLEBeaconTool advertise --major 100 --minor 1
   ```

2. **Run your iOS app** on a physical device

3. **Verify detection** in your iOS app's beacon detection code

4. **Test different scenarios:**
   ```bash
   # Test multiple beacons (run in separate terminals)
   ./BLEBeaconTool advertise --major 100 --minor 1
   ./BLEBeaconTool advertise --major 100 --minor 2
   ./BLEBeaconTool advertise --major 100 --minor 3
   ```

## Requirements

- macOS 12.0+
- Bluetooth LE capable Mac
- Xcode 14+ (for building)
- Swift 5.5+

## License

MIT License - See LICENSE file for details

