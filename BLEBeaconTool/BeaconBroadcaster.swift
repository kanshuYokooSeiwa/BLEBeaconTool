//
//  BeaconBroadcaster.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/05.
//

import Foundation
@preconcurrency import CoreBluetooth
import OSLog

class EnhancediBeaconStrategy: NSObject, BeaconEmissionStrategy, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager!
    private var configuration: BeaconConfiguration?
    private var _isEmitting = false
    private let logger = Logger(subsystem: "com.blebeacon.tool", category: "broadcaster")
    private var continuation: CheckedContinuation<Result<Void, BeaconError>, Never>?
    private var statusTimer: Timer?
    
    var isEmitting: Bool {
        return _isEmitting
    }
    
    var strategyName: String {
        return "Enhanced iBeacon Strategy"
    }
    
    override init() {
        super.init()
    }
    
    func canEmit() async -> Bool {
        return await withCheckedContinuation { continuation in
            let testManager = CBPeripheralManager(delegate: nil, queue: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let canEmit = testManager.state == .poweredOn
                continuation.resume(returning: canEmit)
            }
        }
    }
    
    func startEmission(config: BeaconConfiguration) async -> Result<Void, BeaconError> {
        self.configuration = config
        
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
            
            if config.verbose {
                logger.info("🔄 Initializing Bluetooth peripheral manager...")
                print("🔄 Initializing Bluetooth peripheral manager...")
            }
        }
    }
    
    func stopEmission() async {
        if _isEmitting {
            peripheralManager.stopAdvertising()
            _isEmitting = false
            
            // Stop the status timer
            statusTimer?.invalidate()
            statusTimer = nil
            
            logger.info("🛑 Stopped broadcasting beacon")
            print("🛑 Stopped broadcasting beacon")
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard let continuation = self.continuation else { return }
        
        switch peripheral.state {
        case .poweredOn:
            logger.info("✅ Bluetooth powered on")
            print("✅ Bluetooth powered on")
            startBeaconAdvertising()
        case .poweredOff:
            logger.error("❌ Bluetooth is powered off")
            print("❌ Bluetooth is powered off")
            continuation.resume(returning: .failure(.bluetoothPoweredOff))
            self.continuation = nil
        case .unauthorized:
            logger.error("❌ Bluetooth access unauthorized")
            print("❌ Bluetooth access unauthorized")
            print("💡 Grant Bluetooth permissions in System Settings")
            continuation.resume(returning: .failure(.bluetoothUnauthorized))
            self.continuation = nil
        case .unsupported:
            logger.error("❌ Bluetooth LE advertising not supported")
            print("❌ Bluetooth LE advertising not supported")
            continuation.resume(returning: .failure(.bluetoothUnsupported))
            self.continuation = nil
        case .unknown:
            logger.info("❓ Bluetooth state unknown")
            print("❓ Bluetooth state unknown")
        case .resetting:
            logger.info("🔄 Bluetooth resetting...")
            print("🔄 Bluetooth resetting...")
        @unknown default:
            logger.warning("❓ Unknown Bluetooth state: \(peripheral.state.rawValue)")
            print("❓ Unknown Bluetooth state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard let continuation = self.continuation,
              let config = self.configuration else { return }
        
        if let error = error {
            logger.error("❌ Failed to start advertising: \(error.localizedDescription)")
            print("❌ Failed to start advertising: \(error.localizedDescription)")
            continuation.resume(returning: .failure(.advertisingFailed(error.localizedDescription)))
            self.continuation = nil
        } else {
            _isEmitting = true
            logger.info("✅ Broadcasting iBeacon successfully!")
            print("✅ Broadcasting iBeacon successfully!")
            print("📡 Beacon ID: \(config.localName)")
            
            if config.verbose {
                showBroadcastDetails()
            }
            
            // Show periodic status updates
            startPeriodicStatusUpdates()
            
            continuation.resume(returning: .success(()))
            self.continuation = nil
        }
    }
    
    private func startBeaconAdvertising() {
        guard let config = configuration else {
            continuation?.resume(returning: .failure(.invalidConfiguration("Missing configuration")))
            continuation = nil
            return
        }
        
        if config.verbose {
            logger.info("🚀 Creating iBeacon advertisement data...")
            print("🚀 Creating iBeacon advertisement data...")
        }
        
        // Create iBeacon manufacturer data
        var beaconData = Data()
        beaconData.append(Data([0x4C, 0x00])) // Apple Company ID
        beaconData.append(Data([0x02, 0x15])) // iBeacon type + length
        beaconData.append(withUnsafeBytes(of: config.uuid.uuid) { Data($0) })
        beaconData.append(Data([UInt8(config.major >> 8), UInt8(config.major & 0xFF)]))
        beaconData.append(Data([UInt8(config.minor >> 8), UInt8(config.minor & 0xFF)]))
        beaconData.append(Data([UInt8(bitPattern: config.txPower)]))
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataManufacturerDataKey: beaconData,
            CBAdvertisementDataLocalNameKey: config.localName
        ]
        
        peripheralManager.startAdvertising(advertisementData)
    }
    
    private func showBroadcastDetails() {
        guard let config = configuration else { return }
        
        print("\n📋 Broadcast Details:")
        print("   UUID: \(config.uuid.uuidString)")
        print("   Major: \(config.major)")
        print("   Minor: \(config.minor)")
        print("   TX Power: \(config.txPower) dBm")
        print("   Local Name: \(config.localName)")
        print("   Company ID: 0x004C (Apple)")
        // Show actual iBeacon payload
        showActualPayload()
        print()
    }

    private func showActualPayload() {
        guard let config = configuration else { return }
        
        // Create the actual iBeacon manufacturer data
        var beaconData = Data()
        beaconData.append(Data([0x4C, 0x00])) // Apple Company ID
        beaconData.append(Data([0x02, 0x15])) // iBeacon type + length
        beaconData.append(withUnsafeBytes(of: config.uuid.uuid) { Data($0) })
        beaconData.append(Data([UInt8(config.major >> 8), UInt8(config.major & 0xFF)]))
        beaconData.append(Data([UInt8(config.minor >> 8), UInt8(config.minor & 0xFF)]))
        beaconData.append(Data([UInt8(bitPattern: config.txPower)]))
        
        print("\n📦 Actual iBeacon Payload (\(beaconData.count) bytes):")
        print("   Hex: \(beaconData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("   Breakdown:")
        print("     4C 00          - Apple Company ID")
        print("     02 15          - iBeacon Type & Length")
        print("     \(config.uuid.uuidString.replacingOccurrences(of: "-", with: "").chunked(by: 2).joined(separator: " ")) - UUID")
        print("     \(String(format: "%02X %02X", config.major >> 8, config.major & 0xFF))        - Major (\(config.major))")
        print("     \(String(format: "%02X %02X", config.minor >> 8, config.minor & 0xFF))        - Minor (\(config.minor))")
        print("     \(String(format: "%02X", UInt8(bitPattern: config.txPower)))           - TX Power (\(config.txPower) dBm)")
    }
    
    
    private func startPeriodicStatusUpdates() {
        // Create a background queue for the timer
        let timerQueue = DispatchQueue(label: "beacon.status.timer", qos: .background)
        
        statusTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            DispatchQueue.main.async {
                self.showStatus()
            }
        }
        
        // Add timer to current run loop
        RunLoop.current.add(statusTimer!, forMode: .common)
        
        // Also show initial status after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.showStatus()
        }
    }
    
    private func showStatus() {
        guard let config = configuration else { return }
        
        let timestamp = DateFormatter.timestamp.string(from: Date())
        let status = _isEmitting ? "🟢 ACTIVE" : "🔴 INACTIVE"
        let bluetoothState = getBluetoothStateString()
        
        print("[\(timestamp)] Status: \(status) | BT: \(bluetoothState) | UUID: \(config.uuid.uuidString)")
        print("                   Major: \(config.major) | Minor: \(config.minor) | TX Power: \(config.txPower)dBm")
        print("                   Local Name: \(config.localName)")
        
        if config.verbose {
            print("                   Peripheral Manager State: \(peripheralManager?.state.description ?? "unknown")")
            print("                   Is Advertising: \(peripheralManager?.isAdvertising ?? false)")
        }
        print("") // Empty line for readability
    }
    
    private func getBluetoothStateString() -> String {
        guard let manager = peripheralManager else { return "❓ Unknown" }
        
        switch manager.state {
        case .poweredOn:
            return "✅ On"
        case .poweredOff:
            return "❌ Off"
        case .unauthorized:
            return "🚫 Unauthorized"
        case .unsupported:
            return "❌ Unsupported"
        case .resetting:
            return "🔄 Resetting"
        case .unknown:
            return "❓ Unknown"
        @unknown default:
            return "❓ Unknown(\(manager.state.rawValue))"
        }
    }
}

extension CBManagerState {
    var description: String {
        switch self {
        case .poweredOn:
            return "poweredOn"
        case .poweredOff:
            return "poweredOff"
        case .unauthorized:
            return "unauthorized"
        case .unsupported:
            return "unsupported"
        case .resetting:
            return "resetting"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown(\(rawValue))"
        }
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
