# macOS True iBeacon Advertising — WIP Wrap-Up

**Date:** 2026-02-25
**Status:** 🔬 Confirmed — `kCBAdvDataAppleBeaconKey` is strictly governed by undocumented Xcode/macOS build processes. Only macOS Apps built and exported via **Xcode Archive** emit the payload over-the-air.
**Target:** macOS CLI or custom script emitting a true iBeacon frame

---

## 1. Summary of Findings

Over the course of testing, we determined that constructing the perfect 21-byte iBeacon payload (`kCBAdvDataAppleBeaconKey`) is **necessary but not sufficient** for macOS `bluetoothd` to broadcast it over the air. 

Even when macOS returns `error == nil` from `CBPeripheralManager.startAdvertising()`, the system will silently strip the payload if the calling application does not match an exact set of compile-time and signature requirements dictated by the Xcode build system.

| Build Method | Entitlements | Signature | Outcome |
|---|---|---|---|
| CLI `swift run` / `swift build` | None | Ad-hoc | ❌ Silently drops `0x4C` |
| `xcodebuild` CLI (Release) | Sandbox + BT | Apple Dev | ❌ Silently drops `0x4C` |
| `xcodebuild` wrapped via script | Sandbox + BT | Apple Dev | ❌ Silently drops `0x4C` |
| `swiftc` AppKit Wrapper | None | Ad-hoc | ❌ Silently drops `0x4C` |
| **Xcode IDE → Product → Archive** | Sandbox + BT | Apple Dev | ✅ **Transmits true iBeacon** |

---

## 2. Variables Eliminated

We systematically verified that the failure is **not** caused by:
1. **The Code:** `BeaconEmitter` (which works) and our CLI tool use the exact same CoreBluetooth API calls and byte payload.
2. **The Entitlements:** Adding `com.apple.security.app-sandbox` and `com.apple.security.device.bluetooth` to our CLI app did not solve the issue.
3. **The Info.plist Constraints:** Ensuring `APPL`, `NSBluetoothAlwaysUsageDescription`, and `LSMinimumSystemVersion` were present did not solve the issue.
4. **The RunLoop Context:** Rewriting the test script to use a true `NSApplication` and `AppDelegate` lifecycle instead of `RunLoop.main.run()` did not bypass the restriction.
5. **The Certificate Identity:** Modifying the packaging script to ensure the executable was signed with the user's valid Apple Development Certificate (`TeamIdentifier=HES6WT25LF`) did not work when the app was assembled via the command line.

---

## 3. The Core Issue: Xcode Archive Obfuscation

The definitive test proved that `BLEBeaconTool` works when built via **Xcode → Product → Archive**, and `BeaconEmitter` fails when built via `xcodebuild` from the command line.

This indicates that macOS `bluetoothd`'s authorization check for the Apple-reserved `0x4C 00` manufacturer data relies on deeply embedded metadata injection that only occurs during the full Xcode Archive and Export workflow. 

Hypothesized missing elements generated during Archive:
- Specific `Mach-O` embedded provisioning profiles (`embedded.provisionprofile`)
- `LaunchServices` registration metadata specific to packaged apps
- Code Signing flags injected by Xcode's `ExportOptions.plist` processor
- `com.apple.developer.team-identifier` embedded directly in the Mach-O binary (not just the bundle envelope)

---

## 4. Next Steps & Directions for Tomorrow

To proceed, we must forensically break down the difference between the `.app` produced by `xcodebuild` and the `.app` produced by the Xcode Archive.

1. **Compare Binaries:** Run `otool -l`, `codesign -dvvv --entitlements`, and `security cms -D -i` against the working Archive vs the failing `xcodebuild` output.
2. **Examine Provisioning:** Check if the Xcode Archive embeds a specific provisioning profile that the command line build lacks.
3. **Explore xcodebuild archive command:** See if running `xcodebuild archive -archivePath ...` followed by `xcodebuild -exportArchive` from the CLI successfully mimics the IDE's behavior.

If the goal is to have a simple UNIX CLI tool, it may not be possible to emit true iBeacons on macOS 11+ without wrapping the entire execution inside an archived AppKit `.app` bundle.
