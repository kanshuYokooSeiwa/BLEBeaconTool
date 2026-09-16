import Foundation
import CoreBluetooth

class Broadcaster: NSObject, CBPeripheralManagerDelegate {
    var manager: CBPeripheralManager!
    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            print("Powered on")
            let data: [String: Any] = [
                CBAdvertisementDataManufacturerDataKey: Data([0x4C, 0x00, 0x02, 0x15]),
                CBAdvertisementDataLocalNameKey: "TestBeacon"
            ]
            manager.startAdvertising(data)
        }
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        print("Started advertising, error: \(String(describing: error))")
        exit(0)
    }
}

let b = Broadcaster()
RunLoop.main.run()
