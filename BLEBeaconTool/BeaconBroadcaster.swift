//
//  BeaconBroadcaster.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/05.
//

import Foundation
import CoreBluetooth

class BeaconBroadcaster: NSObject, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager!
    private let uuid: String
    private let major: UInt16
    private let minor: UInt16
    private let txPower: Int8
    private let verbose: Bool
    private var isAdvertising = false
    
    init(uuid: String, major: UInt16, minor: UInt16, txPower: Int8, verbose: Bool) {
        self.uuid = uuid
        self.major = major
        self.minor = minor
        self.txPower = txPower
        self.verbose = verbose
        super.init()
    }
    
    func startBroadcasting() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        if verbose {
            print("🔄 Initializing Bluetooth peripheral manager...")
        }
    }
    
    func stopBroadcasting() {
        if isAdvertising {
            peripheralManager.stopAdvertising()
            isAdvertising = false
            print("🛑 Stopped broadcasting beacon")
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("✅ Bluetooth powered on")
            startBeaconAdvertising()
        case .poweredOff:
            print("❌ Bluetooth is powered off")
            exit(1)
        case .unauthorized:
            print("❌ Bluetooth access unauthorized")
            print("💡 Grant Bluetooth permissions in System Settings")
            exit(1)
        case .unsupported:
            print("❌ Bluetooth LE advertising not supported")
            exit(1)
        case .unknown:
            print("❓ Bluetooth state unknown")
        case .resetting:
            print("🔄 Bluetooth resetting...")
        @unknown default:
            print("❓ Unknown Bluetooth state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("❌ Failed to start advertising: \(error.localizedDescription)")
            exit(1)
        } else {
            isAdvertising = true
            print("✅ Broadcasting iBeacon successfully!")
            print("📡 Beacon ID: TestBeacon-\(major)-\(minor)")
            
            if verbose {
                showBroadcastDetails()
            }
            
            // Show periodic status updates
            Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
                self.showStatus()
            }
        }
    }
    
    private func startBeaconAdvertising() {
        guard let beaconUUID = UUID(uuidString: uuid) else {
            print("❌ Invalid UUID: \(uuid)")
            exit(1)
        }
        
        if verbose {
            print("🚀 Creating iBeacon advertisement data...")
        }
        
        // Create iBeacon manufacturer data
        var beaconData = Data()
        beaconData.append(Data([0x4C, 0x00])) // Apple Company ID
        beaconData.append(Data([0x02, 0x15])) // iBeacon type + length
        beaconData.append(withUnsafeBytes(of: beaconUUID.uuid) { Data($0) })
        beaconData.append(Data([UInt8(major >> 8), UInt8(major & 0xFF)]))
        beaconData.append(Data([UInt8(minor >> 8), UInt8(minor & 0xFF)]))
        beaconData.append(Data([UInt8(bitPattern: txPower)]))
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataManufacturerDataKey: beaconData,
            CBAdvertisementDataLocalNameKey: "\(beaconUUID.uuid)-\(major)-\(minor)"
        ]
        
        peripheralManager.startAdvertising(advertisementData)
    }
    
    private func showBroadcastDetails() {
        print("\n📋 Broadcast Details:")
        print("   UUID: \(uuid)")
        print("   Major: \(major)")
        print("   Minor: \(minor)")
        print("   TX Power: \(txPower) dBm")
        print("   Local Name: BLEBeaconTool-\(major)-\(minor)")
        print("   Company ID: 0x004C (Apple)")
        // Show actual iBeacon payload
        showActualPayload()
        print()
    }

    private func showActualPayload() {
        guard let beaconUUID = UUID(uuidString: uuid) else { return }
        
        // Create the actual iBeacon manufacturer data
        var beaconData = Data()
        beaconData.append(Data([0x4C, 0x00])) // Apple Company ID
        beaconData.append(Data([0x02, 0x15])) // iBeacon type + length
        beaconData.append(withUnsafeBytes(of: beaconUUID.uuid) { Data($0) })
        beaconData.append(Data([UInt8(major >> 8), UInt8(major & 0xFF)]))
        beaconData.append(Data([UInt8(minor >> 8), UInt8(minor & 0xFF)]))
        beaconData.append(Data([UInt8(bitPattern: txPower)]))
        
        print("\n📦 Actual iBeacon Payload (\(beaconData.count) bytes):")
        print("   Hex: \(beaconData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("   Breakdown:")
        print("     4C 00          - Apple Company ID")
        print("     02 15          - iBeacon Type & Length")
        print("     \(beaconUUID.uuidString.replacingOccurrences(of: "-", with: "").chunked(by: 2).joined(separator: " ")) - UUID")
        print("     \(String(format: "%02X %02X", major >> 8, major & 0xFF))        - Major (\(major))")
        print("     \(String(format: "%02X %02X", minor >> 8, minor & 0xFF))        - Minor (\(minor))")
        print("     \(String(format: "%02X", UInt8(bitPattern: txPower)))           - TX Power (\(txPower) dBm)")
    }
    
    private func showStatus() {
        let timestamp = DateFormatter.timestamp.string(from: Date())
        let status = isAdvertising ? "🟢 ACTIVE" : "🔴 INACTIVE"
        print("[\(timestamp)] Status: \(status) | UUID: \(uuid) | Major: \(major) | Minor: \(minor)")
    }
}

extension DateFormatter {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

extension String {
    func chunked(by length: Int) -> [String] {
        return stride(from: 0, to: count, by: length).map {
            let start = index(startIndex, offsetBy: $0)
            let end = index(start, offsetBy: min(length, count - $0))
            return String(self[start..<end])
        }
    }
}
