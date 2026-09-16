import Foundation
import CoreLocation
import CoreBluetooth

let uuid = UUID(uuidString: "92821D61-9FEE-4003-87F1-31799E12017A")!
let region = CLBeaconRegion(uuid: uuid, major: 1, minor: 2, identifier: "Test")
let peripheralData = region.peripheralData(withMeasuredPower: nil) as? [String: Any]
print(peripheralData ?? "nil")
