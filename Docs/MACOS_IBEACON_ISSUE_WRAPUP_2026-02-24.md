# macOS True iBeacon Advertising — WIP Wrap-Up

**Date:** 2026-02-24  
**Status:** 🔬 Unconfirmed — Private key approach implemented, on-air result pending external verification  
**Target:** iOS `CLLocationManager.startRangingBeacons` detecting a beacon broadcast from macOS

---

## 1. Core Problem

macOS `CBPeripheralManager.startAdvertising()` **silently drops** the Apple manufacturer data payload that makes a true iBeacon frame. No error is returned. The advertisement is emitted, but without the `0x4C 0x00 0x02 0x15` header that `CLLocationManager` requires.

| Detection tool | Can detect the Mac's advertisement? |
|---|---|
| iOS `CLLocationManager.startRangingBeacons` | ❌ Requires true iBeacon manufacturer data |
| iOS `CBCentralManager.scanForPeripherals` | ✅ Detects GATT service UUID fallback |
| nRF Connect (iPhone) | ✅ Shows raw advertisement — use this to diagnose |

---

## 2. iBeacon Wire Format Reference

A valid iBeacon BLE advertisement (AD Type `0xFF`):

```
4C 00          Apple Company ID (little-endian)
02 15          iBeacon subtype + length (21 bytes follow)
[16 bytes]     Proximity UUID (big-endian)
[2 bytes]      Major (big-endian)
[2 bytes]      Minor (big-endian)
[1 byte]       Measured TX Power (signed Int8)
```

`CLLocationManager.startRangingBeacons` matches **only** packets with exactly this layout.

---

## 3. Approaches Tried

### 3.1 `CBAdvertisementDataManufacturerDataKey` — public API
**Result: ❌ Silently dropped on macOS 11+**

```swift
peripheralManager.startAdvertising([
    CBAdvertisementDataManufacturerDataKey: data  // 25 bytes with 4C 00 prefix
])
// peripheralManagerDidStartAdvertising fires with error == nil
// Manufacturer data is absent from the actual over-the-air packet
```

---

### 3.2 `kCBAdvDataAppleBeaconKey` — private CoreBluetooth key
**Result: 🔬 Accepted without error on macOS 15.5 — on-air content UNVERIFIED**

Found via Stack Overflow (2013): this is the internal key that `CLBeaconRegion.peripheralData(withMeasuredPower:)` uses on iOS. CoreBluetooth prepends `4C 00 02 15` internally. Our payload is **21 bytes only** (no company ID prefix):

```swift
private static let beaconKey = "kCBAdvDataAppleBeaconKey"

var bytes = [UInt8](repeating: 0, count: 21)
withUnsafeBytes(of: config.uuid.uuid) { ptr in
    for i in 0..<16 { bytes[i] = ptr[i] }
}
bytes[16] = UInt8(config.major >> 8)
bytes[17] = UInt8(config.major & 0xFF)
bytes[18] = UInt8(config.minor >> 8)
bytes[19] = UInt8(config.minor & 0xFF)
bytes[20] = UInt8(bitPattern: config.txPower)

peripheralManager.startAdvertising([beaconKey: Data(bytes)])
```

`peripheralManagerDidStartAdvertising` returns `error == nil` on macOS 15.5.  
**Critical unknown:** does macOS 15 actually emit `4C 00 02 15 ...` on-air, or is it silently dropped again?

---

## 4. Current Strategy Cascade

```
./ble-beacon-tool advertise
    │
    ├─ macOS < 11  → EnhancediBeaconStrategy       standard CBPeripheralManager path
    │
    └─ macOS 11+   → PrivateKeyIBeaconStrategy     kCBAdvDataAppleBeaconKey, 21-byte payload
                          │
                          ├─ accepted (no error)  → broadcasting  ← on-air content UNKNOWN
                          │
                          └─ rejected (error set) → GATTServiceStrategy (auto-fallback)
                                                     detectable by CBCentralManager only
                                                     NOT detectable by CLLocationManager
```

Flags:
- `--strict-ibeacon` — fail hard if private key rejected, no GATT fallback
- `--allow-gatt-fallback` — legacy flag, kept for compatibility

Scanner:
- `--dump-ads` — dumps raw advertisement hex from every nearby peripheral (diagnostic)
- Handles both `4C000215...` and `0215...` manufacturer data variants from CoreBluetooth

---

## 5. 🚨 Critical Verification Checkpoint

**The single most important thing to do next:** confirm whether `kCBAdvDataAppleBeaconKey` actually puts `4C 00 02 15` on-air on macOS 15.

The Mac cannot receive its own BLE advertisements — an external device is required.

---

### Checkpoint A — nRF Connect on iPhone (2 minutes, no code)

1. Start advertising on Mac:
   ```bash
   ./ble-beacon-tool advertise \
     --uuid "92821D61-9FEE-4003-87F1-31799E12017A" \
     --major 0 --minor 1100
   ```
2. Open **nRF Connect for Mobile** on iPhone, tap **Scanner**
3. Find your Mac in the list (look for "MacBook" or the local name)
4. Tap the entry → expand **Advertising Data**

| nRF Connect shows | Conclusion |
|---|---|
| `Manufacturer Data: 4C 00 02 15 92 82 ...` | ✅ True iBeacon on-air. Test with `CLLocationManager` now. |
| No Manufacturer Data entry | ❌ macOS 15 still strips it silently. Move to Option B/C. |
| Manufacturer Data without `4C 00` | ❌ Different frame format. Not iBeacon. |

---

### Checkpoint B — `--dump-ads` on a second Mac

```bash
# On a second Mac near the advertising Mac:
./ble-beacon-tool scan --duration 30 --dump-ads
```

Look for the advertising Mac's entry. The `Mfg data:` line should show `4C 00 02 15 ...` if it works.

---

### Checkpoint C — iOS `CLLocationManager` (definitive)

Run the existing iOS app with `startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: UUID(uuidString: "92821D61-9FEE-4003-87F1-31799E12017A")!))`.

- Ranging results appear within ~5 seconds → ✅ private key works
- Complete silence after 30 seconds → ❌ macOS 15 blocks it

---

## 6. Paths Forward After Verification

### If private key WORKS ✅

- [ ] Extended reliability test: advertise for 30+ minutes, check iOS ranges continuously
- [ ] Bluetooth toggle recovery test (turn BT off and on, confirm re-advertise)
- [ ] Test on macOS 14 Sonoma (confirm cross-version behaviour)
- [ ] Confirm `--strict-ibeacon` path works correctly
- [ ] Update this document with confirmed status

### If private key FAILS ❌

**Path A — Change iOS to `CBCentralManager` (no hardware, fastest)**

Replace `CLLocationManager.startRangingBeacons` in the iOS app with:

```swift
centralManager.scanForPeripherals(
    withServices: [CBUUID(string: "92821D61-9FEE-4003-87F1-31799E12017A")]
)

func centralManager(_ central: CBCentralManager,
                    didDiscover peripheral: CBPeripheral,
                    advertisementData: [String: Any],
                    rssi RSSI: NSNumber) {
    // RSSI-based distance estimation
    // Connect to peripheral to read Major/Minor from characteristic UUID:
    // 92821D61-9FEE-4003-87F1-31799E12017B
}
```

Tradeoff: loses `CLLocationManager` Immediate/Near/Far proximity model.  
The macOS tool already advertises the correct service UUID — no Mac changes needed.

---

**Path B — Raspberry Pi / Linux BlueZ emitter (requires hardware)**

BlueZ `hcitool` can emit a byte-perfect iBeacon frame via raw HCI:

```bash
# UUID: 92821D61-9FEE-4003-87F1-31799E12017A
# Major: 0x0000  Minor: 0x044C  TxPower: 0xC5 (-59 dBm)
sudo hcitool -i hci0 cmd 0x08 0x0008 \
  1e 02 01 1a 1a ff \
  4c 00 02 15 \
  92 82 1d 61 9f ee 40 03 87 f1 31 79 9e 12 01 7a \
  00 00 04 4c c5 00
sudo hcitool -i hci0 cmd 0x08 0x000a 01
```

`CLLocationManager` detects this correctly. iOS app unchanged.  
→ Add as `Scripts/raspberry-pi-ibeacon.sh` in this repo.

---

**Path C — Both A and B**

iOS app uses `CBCentralManager` for macOS/dev testing + Pi script for production/hardware integration.

---

## 7. Open Questions

| # | Question | Impact |
|---|---|---|
| 1 | Does `kCBAdvDataAppleBeaconKey` emit true iBeacon on macOS 15.5? | Unblocks everything if yes |
| 2 | Is modifying the iOS app (`CLLocationManager` → `CBCentralManager`) in scope? | Path A available |
| 3 | Is `CLLocationManager` proximity ranging (Immediate/Near/Far) required? | Rules out GATT path if yes |
| 4 | Is Raspberry Pi / Linux hardware available? | Path B available |
| 5 | Which macOS versions need to be supported? | Determines version test matrix |
| 6 | Is this tool for development use only, or production? | Affects how much Pi path matters |

---

## 8. File Inventory

| File | Role | State |
|---|---|---|
| `BLEBeaconTool/PrivateKeyIBeaconStrategy.swift` | Private key iBeacon attempt | ✅ New |
| `BLEBeaconTool/GATTServiceStrategy.swift` | BLE service UUID fallback | ✅ Working |
| `BLEBeaconTool/BeaconBroadcaster.swift` | Standard iBeacon (macOS < 11) | ✅ Working |
| `BLEBeaconTool/BeaconEmissionStrategy.swift` | Capability detection | ✅ Fixed |
| `BLEBeaconTool/BeaconScanner.swift` | BLE scanner + `--dump-ads` | ✅ Updated |
| `BLEBeaconTool/main.swift` | CLI entry, strategy cascade | ✅ Updated |
| `BLEBeaconTool/BeaconConfiguration.swift` | Config model | ✅ Unchanged |
| `BLEBeaconTool/BeaconError.swift` | Error types | ✅ Updated |

**Build:** `BUILD SUCCEEDED` — Release, arm64, macOS 15.5  
**Binary:** `./ble-beacon-tool`

---

## 9. Quick Test Commands

```bash
# Advertise (private key first, GATT fallback if rejected)
./ble-beacon-tool advertise \
  --uuid "92821D61-9FEE-4003-87F1-31799E12017A" \
  --major 0 --minor 1100

# Advertise — strict mode (fail if true iBeacon not possible)
./ble-beacon-tool advertise \
  --uuid "92821D61-9FEE-4003-87F1-31799E12017A" \
  --major 0 --minor 1100 --strict-ibeacon

# Scan — diagnostic dump of all nearby BLE advertisement raw data
./ble-beacon-tool scan --duration 30 --dump-ads

# Scan — filter to our UUID
./ble-beacon-tool scan \
  --uuid "92821D61-9FEE-4003-87F1-31799E12017A" \
  --duration 30 --verbose
```
