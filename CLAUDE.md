# CLAUDE.md — BLEBeaconTool

## Project Overview

macOS command-line tool for broadcasting and scanning Bluetooth Low Energy (BLE) iBeacon signals. Written in Swift, built with Xcode.

- **Bundle ID**: `com.k-yokoo.BLEBeaconTool`
- **Team ID**: `HES6WT25LF`
- **Min macOS**: 11.0
- **Swift**: 5.5+
- **Dependency**: `swift-argument-parser` 1.7.0 (via SPM)
- **Default test UUID**: `92821D61-9FEE-4003-87F1-31799E12017A`

---

## Architecture

### Source Files (`BLEBeaconTool/`)

| File | Role |
|------|------|
| `main.swift` | CLI entry point. ArgumentParser commands: `advertise`, `scan`, `status` |
| `BeaconEmitter.swift` | Direct CoreBluetooth peripheral implementation matching BeaconEmitter GUI app |
| `BeaconScanner.swift` | Raw BLE scan via `CBCentralManager`. Detects iBeacon manufacturer data |
| `BeaconConfiguration.swift` | Config model with validation. Profiles: `.development`, `.testing`, `.production` |
| `BeaconError.swift` | `BeaconError` enum with `LocalizedError` + `ValidationResult` |
| `SystemStatusChecker.swift` | Diagnostics: Bluetooth state, permissions, macOS version |

---

## Build & Run

### Build (Xcode project — required for entitlements)

```bash
xcodebuild -project BLEBeaconTool.xcodeproj -scheme BLEBeaconTool -configuration Release build
cp ~/Library/Developer/Xcode/DerivedData/BLEBeaconTool-*/Build/Products/Release/BLEBeaconTool ./ble-beacon-tool
```

### Package as App Bundle (required for Bluetooth TCC permissions on macOS)

```bash
./package_app.sh
# Produces BLEBeaconTool.app/ with entitlements, Info.plist, and codesign
```

### Run

```bash
# Always run from within the app bundle for proper TCC association
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool advertise --uuid 92821D61-9FEE-4003-87F1-31799E12017A --major 1 --minor 1
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool scan --duration 30
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool status
```

---

## Important macOS BLE Emission & Verification Notes

1. **Payload Structure**: For iBeacon on macOS, `kCBAdvDataAppleBeaconKey` expects exactly 21 bytes (16 bytes UUID + 2 bytes Major + 2 bytes Minor + 1 byte Measured Power). CoreBluetooth internally wraps this with the Apple Company ID `0x4C00` and iBeacon header `0x0215`.
2. **App Sandbox & Entitlements**: The binary must be packaged inside a `.app` bundle with `com.apple.security.app-sandbox` and `com.apple.security.device.bluetooth` signed by a valid Apple Development identity. Running raw unbundled binaries in Terminal lacks bundle identity and TCC privileges.
3. **External Verification**: A single Mac Bluetooth LE chip cannot scan its own advertisements. Always verify broadcast reception on an external device (e.g. an iPhone running nRF Connect or Locate Beacon, or a second device).

---

## Entitlements & Permissions

`BLEBeaconTool/BLEBeaconTool.entitlements`:
- `com.apple.security.app-sandbox` = true
- `com.apple.security.device.bluetooth` = true

`BLEBeaconTool/Info.plist` keys:
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`
- `CFBundleIdentifier`: `com.k-yokoo.BLEBeaconTool`

Required system permissions: System Settings → Privacy & Security → Bluetooth (for advertising and scanning).

---

## Key Patterns & Conventions

- All strategies implement `BeaconEmissionStrategy` protocol (async `startEmission`, `stopEmission`, `canEmit`)
- Use `CheckedContinuation` to bridge `CBPeripheralManagerDelegate` callbacks into async/await
- `RunLoop.main.run()` keeps the CLI alive for delegate callbacks
- Signal handling (SIGINT) → calls `strategy.stopEmission()` then `exit(0)`
- Status updates printed every 2 seconds via `Timer` on `.common` RunLoop mode
- Emoji prefixes on all user-facing print: `✅ ❌ ⚠️ 💡 📡`
- `DateFormatter.timestamp` extension (HH:mm:ss) shared across strategies in `BeaconBroadcaster.swift`
- `String.chunked(by:)` extension in `BeaconBroadcaster.swift`

---

## Project Files (non-Swift)

| Path | Purpose |
|------|---------|
| `package_app.sh` | Packages binary into `.app` bundle with codesign |
| `BLEBeaconTool.xcodeproj/` | Xcode project (SPM dependency: swift-argument-parser) |
| `BLEBeaconTool.app/` | Built app bundle (not committed) |
| `ble-beacon-tool` | Built binary copy (not committed) |
| `BeaconEmitterClone/` | Reference implementation (SwiftUI app, for comparison) |
| `Docs/` | Investigation and wrap-up reports |

---

## Debugging

```bash
# Verify codesign and entitlements
codesign -dvvv BLEBeaconTool.app
codesign -d --entitlements :- BLEBeaconTool.app

# Monitor Bluetooth system logs
log stream --predicate 'subsystem == "com.apple.bluetooth"'

# Diagnostic BLE scan (dump all raw advertisement data)
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool scan --dump-ads

# Check TCC Bluetooth permissions
sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, allowed FROM access WHERE service LIKE '%bluetooth%';"
```
