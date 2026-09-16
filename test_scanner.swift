import Foundation
import CoreBluetooth

class Sniffer: NSObject, CBCentralManagerDelegate {
    var centralManager: CBCentralManager!
    var count = 0

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth is ON. Scanning for raw BLE packets...")
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else {
            print("Bluetooth state warning: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if mfgData.count >= 4 { // Apple typically uses 0x004C
                let hexString = mfgData.map { String(format: "%02X", $0) }.joined()
                
                // iBeacon payload format starts with 4C000215
                if hexString.hasPrefix("4C000215") {
                    count += 1
                    print("✅ Found an iBeacon! RSSI: \(RSSI)")
                    print("   Raw Manufacturer Data: \(hexString)")
                    
                    // Extract UUID, Major, Minor
                    let uuidHex = String(hexString.dropFirst(8).prefix(32))
                    let majorHex = String(hexString.dropFirst(40).prefix(4))
                    let minorHex = String(hexString.dropFirst(44).prefix(4))
                    
                    if let major = Int(majorHex, radix: 16), let minor = Int(minorHex, radix: 16) {
                        print("   UUID (hex): \(uuidHex)")
                        print("   Major: \(major), Minor: \(minor)\n")
                    }
                }
            }
        }
    }
}

print("Starting CBCentralManager test script...")
let sniffer = Sniffer()

// Run for 30 seconds
RunLoop.main.run(until: Date(timeIntervalSinceNow: 30))
print("\nTest finished. Found \(sniffer.count) iBeacon packets.")
