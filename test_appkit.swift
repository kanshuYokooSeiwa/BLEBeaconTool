import AppKit
import CoreBluetooth
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate, CBPeripheralManagerDelegate {
    var manager: CBPeripheralManager!
    let beaconKey = "kCBAdvDataAppleBeaconKey"

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 AppKit application launched.")
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("Bluetooth state: \(peripheral.state.rawValue)")
        if peripheral.state == .poweredOn {
            print("Powered on, attempting to advertise...")
            
            // Build the exact 21-byte payload the scanner is looking for
            let uuid = NSUUID(uuidString: "92821D61-9FEE-4003-87F1-31799E12017A")!
            var advBytes = [CUnsignedChar](repeating: 0, count: 21)
            uuid.getBytes(&advBytes)
            
            // Major: 0, Minor: 1100
            advBytes[16] = 0
            advBytes[17] = 0
            advBytes[18] = 4
            advBytes[19] = 76
            advBytes[20] = CUnsignedChar(bitPattern: -59)
            
            let advData = Data(bytes: &advBytes, count: 21)
            
            manager.startAdvertising([beaconKey: advData])
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("❌ Error starting advertising: \(error.localizedDescription)")
            NSApplication.shared.terminate(nil)
        } else {
            print("✅ Successfully started advertising with AppKit!")
            print("Verify with your iPhone now. Stopping in 30 seconds.")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                print("Stopping...")
                self.manager.stopAdvertising()
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
