# Contributing to BLE Beacon Tool

## Technical Architecture

### Core Components

1. **Main Command Parser** (`main.swift`)
   - Uses Swift ArgumentParser for CLI interface
   - Defines subcommands: `advertise`, `scan`, `status`
   - Handles argument validation and routing

2. **BeaconBroadcaster** (`BeaconBroadcaster.swift`)
   - Implements `CBPeripheralManagerDelegate`
   - Manages iBeacon advertisement lifecycle
   - Handles Bluetooth state changes and permissions

3. **BeaconScanner** (`BeaconScanner.swift`) 
   - Implements `CLLocationManagerDelegate`
   - Uses Core Location for iBeacon ranging
   - Filters and reports discovered beacons

4. **SystemStatusChecker** (`SystemStatusChecker.swift`)
   - Implements `CBCentralManagerDelegate`
   - Diagnoses Bluetooth and permission issues
   - Provides troubleshooting guidance

### iBeacon Data Format

Our tool generates standard iBeacon manufacturer data:

```
Offset | Length | Description
-------|--------|-------------
0      | 2      | Apple Company ID (0x004C)
2      | 1      | iBeacon Type (0x02)
3      | 1      | Data Length (0x15 = 21 bytes)
4      | 16     | UUID (128-bit)
20     | 2      | Major (big-endian)
22     | 2      | Minor (big-endian)
24     | 1      | TX Power (signed)
```

### Permission Requirements

#### Bluetooth Broadcasting
- **Framework:** Core Bluetooth
- **Capability:** `com.apple.developer.bluetooth-central` (automatic)
- **System Permission:** Privacy & Security → Bluetooth
- **Delegate:** `CBPeripheralManagerDelegate`

#### Beacon Scanning  
- **Framework:** Core Location + Core Bluetooth
- **Capability:** Location services
- **System Permission:** Privacy & Security → Location Services
- **Delegate:** `CLLocationManagerDelegate`

## Development Setup

### Prerequisites
```bash
# Xcode Command Line Tools
xcode-select --install

# Swift Package Manager (included with Xcode)
swift --version
```

### Project Structure
```
BLEBeaconTool/
├── main.swift              # CLI entry point and argument parsing
├── BeaconBroadcaster.swift  # Core Bluetooth advertising
├── BeaconScanner.swift      # Core Location beacon ranging  
├── SystemStatusChecker.swift # System diagnostics
├── Package.swift            # SPM dependencies
├── README.md               # User documentation
└── CONTRIBUTING.md         # This file
```

### Building
```bash
# Debug build
swift build

# Release build  
swift build -c release

# Run directly
swift run BLEBeaconTool advertise --verbose
```

### Testing
```bash
# Basic functionality test
./BLEBeaconTool status

# Broadcasting test (requires Bluetooth permissions)
./BLEBeaconTool advertise --major 999 --minor 1 --verbose

# Scanning test (requires Location + Bluetooth permissions)
./BLEBeaconTool scan --duration 10 --verbose
```

## Implementation Notes

### Bluetooth State Management

The tool follows Apple's recommended Bluetooth state handling:

```swift
func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    switch peripheral.state {
    case .poweredOn:
        // Safe to start advertising
    case .unauthorized:
        // Request permissions and exit gracefully
    case .unsupported:
        // Hardware limitation - cannot proceed
    // ... handle other states
    }
}
```

### Error Handling Strategy

1. **Permission Errors:** Provide clear instructions and exit cleanly
2. **Hardware Errors:** Detect unsupported devices and fail gracefully  
3. **Input Validation:** Validate UUIDs, ranges, and parameters before use
4. **Signal Handling:** Clean up Bluetooth resources on interrupt

### Memory Management

- **Delegates:** Use `weak` references where appropriate
- **Timers:** Invalidate timers in cleanup methods
- **Core Bluetooth:** Stop advertising/scanning before deallocation
- **RunLoop:** Use `RunLoop.main.run()` for persistent operations

### UUID Validation

```swift
func validateUUID(_ uuidString: String) -> Bool {
    return UUID(uuidString: uuidString) != nil
}
```

### TX Power Mapping

TX Power affects advertisement strength and battery consumption:

| Value | dBm | Range | Battery Impact |
|-------|-----|-------|----------------|
| -59   | -59 | ~1m   | Lowest |
| -30   | -30 | ~10m  | Low |
| -12   | -12 | ~70m  | Medium |
| 4     | +4  | ~100m | High |

## Future Enhancements

### High Priority
- [ ] **Configuration files** for saved beacon profiles
- [ ] **Batch mode** for multiple simultaneous beacons  
- [ ] **JSON output** for programmatic integration
- [ ] **Signal strength monitoring** during broadcast

### Medium Priority
- [ ] **Web dashboard** for remote monitoring
- [ ] **Logging to file** with rotation
- [ ] **Performance metrics** (CPU, battery impact)
- [ ] **Custom manufacturer data** beyond iBeacon format

### Low Priority  
- [ ] **Eddystone support** (Google's beacon format)
- [ ] **AltBeacon support** (open source format)
- [ ] **GUI version** using SwiftUI
- [ ] **iOS companion app**

## Code Style Guidelines

### Swift Style
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable names: `peripheralManager` not `pm`
- Prefer explicit types for clarity: `let major: UInt16 = 100`
- Group related functionality with `// MARK:` comments

### Error Messages
- Use emoji prefixes for visual scanning: ✅ ❌ ⚠️ 💡
- Provide actionable solutions: "Grant permissions in System Settings"
- Include relevant context: state values, error codes

### Documentation
- Document all public APIs with Swift doc comments
- Include usage examples in complex functions
- Explain non-obvious business logic

## Testing Strategies

### Unit Testing
```bash
# Add to Package.swift
.testTarget(
    name: "BLEBeaconToolTests",
    dependencies: ["BLEBeaconTool"]
)
```

### Integration Testing
1. **Permission Simulation:** Mock Core Bluetooth states
2. **Advertisement Validation:** Use secondary device to detect beacons
3. **Parameter Validation:** Test edge cases and invalid inputs

### Manual Testing Checklist
- [ ] Tool builds without warnings
- [ ] All subcommands parse arguments correctly
- [ ] Bluetooth permission flow works
- [ ] Location permission flow works  
- [ ] Broadcasting generates detectable beacons
- [ ] Scanning discovers known beacons
- [ ] Status command reports accurate information
- [ ] Error messages are helpful and actionable

## Release Process

1. **Version Bump:** Update version in relevant files
2. **Testing:** Run full test suite and manual verification
3. **Documentation:** Update README.md with new features/changes
4. **Build:** Create release build with optimizations
5. **Archive:** Package binary and documentation
6. **Tag:** Create git tag with version number

## Debugging Tips

### Bluetooth Issues
```bash
# Reset Bluetooth daemon (requires admin)
sudo pkill bluetoothd

# Check Bluetooth hardware
system_profiler SPBluetoothDataType

# Monitor system logs
log stream --predicate 'subsystem == "com.apple.bluetooth"'
```

### Permission Issues
```bash
# Check TCC database for permissions
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, allowed FROM access WHERE service LIKE '%bluetooth%';"
```

### Core Location Issues
```bash
# Check location services status
defaults read /var/db/locationd/clients.plist
```

## Contact & Support

- **Issues:** Use GitHub Issues for bug reports and feature requests
- **Discussions:** Use GitHub Discussions for questions and ideas
- **Security:** Report security issues privately via email

## License

MIT License - contributions welcome under the same terms.

