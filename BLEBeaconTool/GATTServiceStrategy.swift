//
//  GATTServiceStrategy.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/06.
//

import Foundation
@preconcurrency import CoreBluetooth
import OSLog

class GATTServiceStrategy: NSObject, BeaconEmissionStrategy, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager!
    private var configuration: BeaconConfiguration?
    private var beaconCharacteristic: CBMutableCharacteristic?
    private var statusTimer: Timer?
    private var _isEmitting = false
    private let logger = Logger(subsystem: "com.blebeacon.tool", category: "gatt-strategy")
    private var continuation: CheckedContinuation<Result<Void, BeaconError>, Never>?
    private let statusUpdateInterval: TimeInterval = 2.0
    
    // Custom service UUID for fallback beacon
    private var beaconServiceUUID = CBUUID(string: "92821D61-9FEE-4003-87F1-31799E12017A")
    private let beaconCharacteristicUUID = CBUUID(string: "92821D61-9FEE-4003-87F1-31799E12017B")
    
    var isEmitting: Bool {
        return _isEmitting
    }
    
    var strategyName: String {
        return "GATT Service Strategy (Fallback)"
    }
    
    override init() {
        super.init()
    }
    
    func canEmit() async -> Bool {
        return await withCheckedContinuation { continuation in
            let testManager = CBPeripheralManager(delegate: nil, queue: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // GATT services are more permissive than iBeacon advertising
                let canEmit = testManager.state == .poweredOn || testManager.state == .unknown
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
                logger.info("🔄 Initializing GATT service strategy...")
                print("🔄 Initializing GATT service strategy (fallback mode)")
            }
        }
    }
    
    func stopEmission() async {
        if _isEmitting {
            peripheralManager.removeAllServices()
            peripheralManager.stopAdvertising()
            _isEmitting = false
            statusTimer?.invalidate()
            statusTimer = nil
            logger.info("🛑 Stopped GATT service advertising")
            print("🛑 Stopped GATT service advertising")
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard let continuation = self.continuation else { return }
        
        switch peripheral.state {
        case .poweredOn:
            logger.info("✅ Bluetooth powered on - starting GATT service")
            print("✅ Bluetooth powered on - starting GATT service")
            setupGATTService()
        case .poweredOff:
            logger.error("❌ Bluetooth is powered off")
            print("❌ Bluetooth is powered off")
            continuation.resume(returning: .failure(.bluetoothPoweredOff))
            self.continuation = nil
        case .unauthorized:
            logger.error("❌ Bluetooth access unauthorized")
            print("❌ Bluetooth access unauthorized")
            continuation.resume(returning: .failure(.bluetoothUnauthorized))
            self.continuation = nil
        case .unsupported:
            logger.error("❌ Bluetooth LE not supported")
            print("❌ Bluetooth LE not supported")
            continuation.resume(returning: .failure(.bluetoothUnsupported))
            self.continuation = nil
        default:
            logger.info("🔄 Bluetooth state: \(peripheral.state.rawValue)")
            print("🔄 Bluetooth state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard let continuation = self.continuation else { return }
        
        if let error = error {
            logger.error("❌ Failed to add GATT service: \(error.localizedDescription)")
            print("❌ Failed to add GATT service: \(error.localizedDescription)")
            continuation.resume(returning: .failure(.advertisingFailed(error.localizedDescription)))
            self.continuation = nil
        } else {
            logger.info("✅ GATT service added successfully")
            print("✅ GATT service added successfully")
            startGATTAdvertising()
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard let continuation = self.continuation,
              let config = self.configuration else { return }
        
        if let error = error {
            logger.error("❌ Failed to start GATT advertising: \(error.localizedDescription)")
            print("❌ Failed to start GATT advertising: \(error.localizedDescription)")
            continuation.resume(returning: .failure(.advertisingFailed(error.localizedDescription)))
            self.continuation = nil
        } else {
            _isEmitting = true
            logger.info("✅ GATT service broadcasting successfully!")
            print("✅ GATT service broadcasting successfully!")
            print("📡 Beacon ID: \(config.localName) (GATT mode)")
            print("📡 Service UUID: \(beaconServiceUUID.uuidString)")
            print("⚠️ GATT fallback is not a standard iBeacon frame; iBeacon-only scanners may not detect it")
            
            if config.verbose {
                showGATTDetails()
            }

            startPeriodicStatusUpdates()
            
            continuation.resume(returning: .success(()))
            self.continuation = nil
        }
    }
    
    private func setupGATTService() {
        guard let config = configuration else {
            continuation?.resume(returning: .failure(.invalidConfiguration("Missing configuration")))
            continuation = nil
            return
        }

        beaconServiceUUID = CBUUID(nsuuid: config.uuid)
        
        // Create beacon data characteristic
        let characteristic = CBMutableCharacteristic(
            type: beaconCharacteristicUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        beaconCharacteristic = characteristic
        
        let service = CBMutableService(type: beaconServiceUUID, primary: true)
        service.characteristics = [characteristic]
        
        peripheralManager.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == beaconCharacteristicUUID,
              let config = configuration else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }

        let beaconData = createBeaconData(config: config)
        request.value = beaconData
        peripheral.respond(to: request, withResult: .success)
    }
    
    private func startGATTAdvertising() {
        guard let config = configuration else { return }
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [beaconServiceUUID],
            CBAdvertisementDataLocalNameKey: config.localName
        ]
        
        peripheralManager.startAdvertising(advertisementData)
    }
    
    private func createBeaconData(config: BeaconConfiguration) -> Data {
        var data = Data()
        
        // Custom beacon format for GATT
        data.append(withUnsafeBytes(of: config.uuid.uuid) { Data($0) })
        data.append(Data([UInt8(config.major >> 8), UInt8(config.major & 0xFF)]))
        data.append(Data([UInt8(config.minor >> 8), UInt8(config.minor & 0xFF)]))
        data.append(Data([UInt8(bitPattern: config.txPower)]))
        
        return data
    }
    
    private func showGATTDetails() {
        guard let config = configuration else { return }
        
        print("\n📋 GATT Service Details:")
        print("   Service UUID: \(beaconServiceUUID)")
        print("   Characteristic UUID: \(beaconCharacteristicUUID)")
        print("   Beacon UUID: \(config.uuid.uuidString)")
        print("   Major: \(config.major)")
        print("   Minor: \(config.minor)")
        print("   TX Power: \(config.txPower) dBm")
        print("   Local Name: \(config.localName)")
        print("   Note: This is a fallback mode - not standard iBeacon format")
        print()
    }

    private func startPeriodicStatusUpdates() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: statusUpdateInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                self.showStatus()
            }
        }

        if let statusTimer {
            RunLoop.current.add(statusTimer, forMode: .common)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + statusUpdateInterval) {
            self.showStatus()
        }
    }

    private func showStatus() {
        guard let config = configuration else { return }

        let timestamp = DateFormatter.timestamp.string(from: Date())
        let status = _isEmitting ? "🟢 ACTIVE" : "🔴 INACTIVE"
        print("[\(timestamp)] Status: \(status) | Mode: GATT fallback | Service UUID: \(beaconServiceUUID.uuidString)")
        print("                   Beacon UUID: \(config.uuid.uuidString) | Major: \(config.major) | Minor: \(config.minor)")
        print("")
    }
}

// MARK: - Simulated Beacon Strategy for Testing

class SimulatedBeaconStrategy: BeaconEmissionStrategy, @unchecked Sendable {
    private var _isEmitting = false
    private var simulationTimer: Timer?
    private var configuration: BeaconConfiguration?
    
    var isEmitting: Bool {
        return _isEmitting
    }
    
    var strategyName: String {
        return "Simulated Beacon Strategy (Testing)"
    }
    
    func canEmit() async -> Bool {
        return true // Simulation always available
    }
    
    func startEmission(config: BeaconConfiguration) async -> Result<Void, BeaconError> {
        self.configuration = config
        _isEmitting = true
        
        print("🔧 Starting simulated beacon (for testing purposes)")
        print("📡 Beacon ID: \(config.localName) (SIMULATION)")
        
        if config.verbose {
            showSimulationDetails()
        }
        
        // Start periodic status updates
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.showSimulatedStatus()
        }
        
        return .success(())
    }
    
    func stopEmission() async {
        _isEmitting = false
        simulationTimer?.invalidate()
        simulationTimer = nil
        print("🛑 Stopped simulated beacon")
    }
    
    private func showSimulationDetails() {
        guard let config = configuration else { return }
        
        print("\n📋 Simulated Beacon Details:")
        print("   UUID: \(config.uuid.uuidString)")
        print("   Major: \(config.major)")
        print("   Minor: \(config.minor)")
        print("   TX Power: \(config.txPower) dBm")
        print("   Local Name: \(config.localName)")
        print("   Note: This is a simulation for testing - no actual BLE transmission")
        print()
    }
    
    private func showSimulatedStatus() {
        guard let config = configuration else { return }
        
        let timestamp = DateFormatter.timestamp.string(from: Date())
        let status = _isEmitting ? "🟡 SIMULATED" : "🔴 INACTIVE"
        print("[\(timestamp)] Status: \(status) | UUID: \(config.uuid.uuidString) | Major: \(config.major) | Minor: \(config.minor)")
    }
}