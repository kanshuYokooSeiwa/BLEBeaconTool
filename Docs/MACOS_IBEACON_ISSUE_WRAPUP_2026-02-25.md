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

## 4. Detailed Forensic Comparison

To isolate the exact restrictions, we dumped the properties of the working `BeaconEmitter.app` (built via Xcode Archive) and compared them to our failing `BLEBeaconTool.app` (built and packaged via `xcodebuild` + shell script).

### A. Entitlements Comparison (`codesign -d --entitlements :- <app>`)

Both the working Archive and the failing CLI build share the **exact same** active entitlements:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.bluetooth</key>
    <true/>
</dict>
</plist>
```
*Conclusion: Entitlements are identical. The Sandbox and Bluetooth keys are present, but insufficient on their own.*

### B. Info.plist Comparison

We compared the `Info.plist` of the working Archive against the `Info.plist` injected into our script-packaged CLI bundle.

**Working Archive `BeaconEmitter/Info.plist` Key Attributes:**
```xml
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>LSApplicationCategoryType</key>
<string>public.app-category.developer-tools</string>
<key>LSMinimumSystemVersion</key>
<string>11.0</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>We need your permission to use Bluetooth to share iBeacon</string>
<key>BuildMachineOSBuild</key>
<string>24G419</string>
<key>DTCompiler</key>
<string>com.apple.compilers.llvm.clang.1_0</string>
<!-- ... other DT (Developer Tool) Xcode build tags ... -->
```

**Failing CLI Bundle `BLEBeaconTool/Info.plist` Attributes:**
```xml
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>LSMinimumSystemVersion</key>
<string>11.0</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs Bluetooth access to broadcast and scan for BLE beacons.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app needs Bluetooth peripheral access to broadcast iBeacon signals.</string>
```

*Conclusion: Our CLI bundle mimics the essential `APPL` wrapper, OS version limits, and privacy strings. The Archive possesses additional `DT...` tags tracking the Xcode compiler versions and `BuildMachineOSBuild`, but these are standard IDE artifacts, not security directives.*

### C. Signature Comparison (`codesign -dvv <app>`)

We modified the deployment script to extract the exact `Apple Development: ... (G5LG9DJHK5)` signature from the `xcodebuild` output and apply it to the final App Bundle.

**Working Archive:**
```text
Format=bundle with Mach-O thin (arm64)
Signature size=4792
Authority=Apple Development: 太郎 生和 (G5LG9DJHK5)
TeamIdentifier=HES6WT25LF
```

**Failing CLI Bundle:**
```text
Format=app bundle with Mach-O thin (arm64)
Signature size=4792
Authority=Apple Development: 太郎 生和 (G5LG9DJHK5)
TeamIdentifier=HES6WT25LF
```

*Conclusion: Both binaries report the exact same valid Developer Authority and Team ID, verifying that the packaging script correctly applied the signature.*

### D. The Missing Link

With Code Signatures, Entitlements, and Info.plist constraints perfectly mirrored, the restriction limiting `bluetoothd` payload access must exist in **Embedded Provisioning** or **Mach-O load commands** (like restricted runtime attributes) applied uniquely by Xcode's Archive exporter.

---

## 4. Next Steps & Directions for Tomorrow

To proceed, we must forensically break down the difference between the `.app` produced by `xcodebuild` and the `.app` produced by the Xcode Archive.

1. **Compare Binaries:** Run `otool -l`, `codesign -dvvv --entitlements`, and `security cms -D -i` against the working Archive vs the failing `xcodebuild` output.
2. **Examine Provisioning:** Check if the Xcode Archive embeds a specific provisioning profile that the command line build lacks.
3. **Explore xcodebuild archive command:** See if running `xcodebuild archive -archivePath ...` followed by `xcodebuild -exportArchive` from the CLI successfully mimics the IDE's behavior.

If the goal is to have a simple UNIX CLI tool, it may not be possible to emit true iBeacons on macOS 11+ without wrapping the entire execution inside an archived AppKit `.app` bundle.
