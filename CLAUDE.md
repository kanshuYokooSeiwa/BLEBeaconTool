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
| `BeaconBroadcaster.swift` | `EnhancediBeaconStrategy` — standard CBPeripheral iBeacon (macOS <11) |
| `PrivateKeyIBeaconStrategy.swift` | Uses private key `kCBAdvDataAppleBeaconKey` to attempt true iBeacon on macOS 11+ |
| `GATTServiceStrategy.swift` | GATT service fallback + `SimulatedBeaconStrategy` (testing only) |
| `BeaconScanner.swift` | Raw BLE scan via `CBCentralManager`. Detects iBeacon manufacturer data and GATT fallback beacons |
| `BeaconEmissionStrategy.swift` | `BeaconEmissionStrategy` protocol + `SystemCapabilityDetector` |
| `BeaconConfiguration.swift` | Config model with validation. Profiles: `.development`, `.testing`, `.production` |
| `BeaconError.swift` | `BeaconError` enum with `LocalizedError` + `ValidationResult` |
| `SystemStatusChecker.swift` | Diagnostics: Bluetooth state, permissions, macOS version |

### Advertising Strategy Cascade (`main.swift`)

```
macOS < 11  → EnhancediBeaconStrategy (CBAdvertisementDataManufacturerDataKey)
macOS 11+   → PrivateKeyIBeaconStrategy (kCBAdvDataAppleBeaconKey)
               └─ rejected → GATTServiceStrategy (fallback, --allow-gatt-fallback)
--strict-ibeacon → fail instead of GATT fallback
```

### iBeacon Payload Format (25 bytes manufacturer data)

```
Offset  Len  Content
0       2    Apple Company ID: 4C 00
2       1    iBeacon type: 02
3       1    Data length: 15 (21)
4       16   UUID (big-endian)
20      2    Major (big-endian)
22      2    Minor (big-endian)
24      1    TX Power (signed Int8)
```

When using `kCBAdvDataAppleBeaconKey`, only the 21-byte payload (bytes 4-24) is passed; CoreBluetooth prepends `4C 00 02 15` internally.

---

## Build & Run

### Build (Xcode project — required for entitlements)

```bash
xcodebuild -project BLEBeaconTool.xcodeproj -scheme BLEBeaconTool -configuration Release build
cp ~/Library/Developer/Xcode/DerivedData/BLEBeaconTool-*/Build/Products/Release/BLEBeaconTool ./ble-beacon-tool
```

### Package as App Bundle (required for Bluetooth TCC permissions on macOS 15+)

```bash
./package_app.sh
# Produces BLEBeaconTool.app/ with entitlements, Info.plist, and codesign
```

### Run

```bash
# Always run from within the app bundle for proper TCC association
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool advertise
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool scan --duration 30
./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool status
```

---

## CLI Commands & Options

| Command | Key Options |
|---------|-------------|
| `advertise` | `--uuid`, `--major`, `--minor`, `--power`, `--allow-gatt-fallback`, `--strict-ibeacon`, `--verbose` |
| `scan` | `--uuid` (optional filter), `--duration` (default 30s), `--verbose`, `--dump-ads` (diagnostic) |
| `status` | none |

Defaults: UUID=`92821D61-9FEE-4003-87F1-31799E12017A`, Major=100, Minor=1, Power=-59 dBm.

---

## Critical macOS iBeacon Restriction (IMPORTANT)

macOS 11+ **silently drops** Apple `0x4C` manufacturer data from BLE advertisements for apps not built via **Xcode IDE → Product → Archive**. This is a `bluetoothd` restriction, NOT a code issue.

| Build Method | True iBeacon OTA |
|---|---|
| `swift build` / `swift run` | Silently dropped |
| `xcodebuild` CLI | Silently dropped |
| Script-packaged `.app` | Silently dropped |
| **Xcode Archive (IDE)** | **Works** |

**Consequence**: `kCBAdvDataAppleBeaconKey` will return `error == nil` (accepted by CoreBluetooth) but the `0x4C` frame is still dropped at the `bluetoothd` layer unless the binary was produced by Xcode Archive.

**GATT fallback is always available** but is NOT detectable by iOS `CLLocationManager.startRangingBeacons()` — only by `CBCentralManager` scanning.

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
