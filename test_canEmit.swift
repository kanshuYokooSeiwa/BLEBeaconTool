import Foundation
import CoreBluetooth

func canEmit() {
    let testManager = CBPeripheralManager(delegate: nil, queue: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let canEmit = testManager.state == .poweredOn
        print("canEmit: \(canEmit), state: \(testManager.state.rawValue)")
        exit(0)
    }
}

canEmit()
RunLoop.main.run()
