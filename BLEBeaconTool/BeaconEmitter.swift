//
//  BeaconEmitter.swift
//  BLEBeaconTool
//
//  Unified beacon emitter. Replaces EnhancediBeaconStrategy,
//  PrivateKeyIBeaconStrategy, and GATTServiceStrategy.
//
//  One CBPeripheralManager, one delegate, one source of truth.
//  Supports two emission modes:
//    .iBeacon — kCBAdvDataAppleBeaconKey (true iBeacon if built via Xcode Archive)
//    .gatt    — CBAdvertisementDataServiceUUIDsKey (always works, not standard iBeacon)
//

import Foundation
@preconcurrency import CoreBluetooth
import OSLog

// MARK: - EmissionMode

enum EmissionMode: String {
    case iBeacon = "iBeacon"
    case gatt    = "GATT"
}

// MARK: - BeaconEmitter

class BeaconEmitter: NSObject, CBPeripheralManagerDelegate {

    // MARK: - Private CoreBluetooth key
    private static let appleBeaconKey = "kCBAdvDataAppleBeaconKey"

    // MARK: - State
    private var peripheralManager: CBPeripheralManager?
    private var configuration: BeaconConfiguration?
    private var mode: EmissionMode = .iBeacon
    private var _isEmitting = false
    private let logger = Logger(subsystem: "com.blebeacon.tool", category: "emitter")
    private var continuation: CheckedContinuation<Result<Void, BeaconError>, Never>?
    private var advertisingStartTime: Date?

    // GATT-specific state
    private var beaconServiceUUID: CBUUID?
    private let beaconCharacteristicUUID = CBUUID(string: "92821D61-9FEE-4003-87F1-31799E12017B")
    private var beaconCharacteristic: CBMutableCharacteristic?

    var isEmitting: Bool { _isEmitting }

    // MARK: - Public API

    /// Start emitting a beacon with the given configuration and mode.
    /// Returns once CoreBluetooth has accepted (or rejected) the advertisement.
    func startEmission(config: BeaconConfiguration, mode: EmissionMode) async -> Result<Void, BeaconError> {
        self.configuration = config
        self.mode = mode

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
            if config.verbose {
                logger.info("🔄 Initializing BeaconEmitter (mode: \(mode.rawValue))...")
                print("🔄 Initializing BeaconEmitter (mode: \(mode.rawValue))...")
            }
        }
    }

    /// Stop emitting.
    func stopEmission() {
        guard _isEmitting else { return }
        if mode == .gatt {
            peripheralManager?.removeAllServices()
        }
        peripheralManager?.stopAdvertising()
        _isEmitting = false
        logger.info("🛑 Stopped beacon emission (\(self.mode.rawValue) mode)")
        print("🛑 Stopped beacon emission (\(mode.rawValue) mode)")
    }

    // MARK: - iBeacon Payload Construction

    /// Builds the 21-byte iBeacon payload.
    /// CoreBluetooth prepends 4C 00 02 15 internally when using kCBAdvDataAppleBeaconKey.
    private func buildIBeaconPayload(config: BeaconConfiguration) -> Data {
        var advBytes = [CUnsignedChar](repeating: 0, count: 21)

        (config.uuid as NSUUID).getBytes(&advBytes)

        advBytes[16] = CUnsignedChar((config.major >> 8) & 255)
        advBytes[17] = CUnsignedChar(config.major & 255)

        advBytes[18] = CUnsignedChar((config.minor >> 8) & 255)
        advBytes[19] = CUnsignedChar(config.minor & 255)

        advBytes[20] = CUnsignedChar(bitPattern: config.txPower)

        if config.verbose {
            let hex = advBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("📦 iBeacon payload (21 bytes): \(hex)")
            print("   (CoreBluetooth prepends: 4C 00 02 15)")
        }

        return Data(bytes: &advBytes, count: 21)
    }

    // MARK: - GATT Service Setup

    private func setupGATTService() {
        guard let config = configuration else {
            continuation?.resume(returning: .failure(.invalidConfiguration("Missing configuration")))
            continuation = nil
            return
        }

        beaconServiceUUID = CBUUID(nsuuid: config.uuid)

        let characteristic = CBMutableCharacteristic(
            type: beaconCharacteristicUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        beaconCharacteristic = characteristic

        let service = CBMutableService(type: beaconServiceUUID!, primary: true)
        service.characteristics = [characteristic]

        peripheralManager?.add(service)
    }

    private func createGATTBeaconData(config: BeaconConfiguration) -> Data {
        var data = Data()
        data.append(withUnsafeBytes(of: config.uuid.uuid) { Data($0) })
        data.append(Data([UInt8(config.major >> 8), UInt8(config.major & 0xFF)]))
        data.append(Data([UInt8(config.minor >> 8), UInt8(config.minor & 0xFF)]))
        data.append(Data([UInt8(bitPattern: config.txPower)]))
        return data
    }

    private func startGATTAdvertising() {
        guard let config = configuration, let serviceUUID = beaconServiceUUID else { return }

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: config.localName
        ]

        peripheralManager?.startAdvertising(advertisementData)
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            logger.info("✅ Bluetooth powered on")
            print("✅ Bluetooth powered on")

            guard let config = configuration else {
                continuation?.resume(returning: .failure(.invalidConfiguration("Missing configuration")))
                continuation = nil
                return
            }

            switch mode {
            case .iBeacon:
                let payload = buildIBeaconPayload(config: config)
                let advertisingData: [String: Any] = [
                    BeaconEmitter.appleBeaconKey: payload
                ]
                peripheral.startAdvertising(advertisingData)

            case .gatt:
                setupGATTService()
            }

        case .poweredOff:
            logger.error("❌ Bluetooth is powered off")
            print("❌ Bluetooth is powered off")
            continuation?.resume(returning: .failure(.bluetoothPoweredOff))
            continuation = nil

        case .unauthorized:
            logger.error("❌ Bluetooth access unauthorized")
            print("❌ Bluetooth access unauthorized")
            continuation?.resume(returning: .failure(.bluetoothUnauthorized))
            continuation = nil

        case .unsupported:
            logger.error("❌ Bluetooth LE not supported")
            print("❌ Bluetooth LE not supported")
            continuation?.resume(returning: .failure(.bluetoothUnsupported))
            continuation = nil

        default:
            logger.info("🔄 Bluetooth state: \(peripheral.state.rawValue)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            logger.error("❌ Failed to add GATT service: \(error.localizedDescription)")
            print("❌ Failed to add GATT service: \(error.localizedDescription)")
            continuation?.resume(returning: .failure(.advertisingFailed(error.localizedDescription)))
            continuation = nil
        } else {
            logger.info("✅ GATT service added")
            print("✅ GATT service added")
            startGATTAdvertising()
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard let config = configuration else { return }

        if let error = error {
            logger.error("❌ Advertising failed: \(error.localizedDescription)")
            print("❌ Advertising failed: \(error.localizedDescription)")
            continuation?.resume(returning: .failure(.advertisingFailed(error.localizedDescription)))
            continuation = nil
        } else {
            _isEmitting = true
            advertisingStartTime = Date()

            switch mode {
            case .iBeacon:
                print("✅ CB stack accepted iBeacon advertisement")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("   UUID  : \(config.uuid.uuidString)")
                print("   Major : \(config.major)")
                print("   Minor : \(config.minor)")
                print("   Power : \(config.txPower) dBm")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            case .gatt:
                print("✅ GATT service broadcasting")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("   Service UUID: \(beaconServiceUUID?.uuidString ?? "N/A")")
                print("   Local Name  : \(config.localName)")
                print("   Beacon UUID : \(config.uuid.uuidString)")
                print("   Major       : \(config.major)")
                print("   Minor       : \(config.minor)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("⚠️  GATT mode is NOT a standard iBeacon frame")
                print("   iOS CLLocationManager will NOT detect this beacon")
                print("   Use CBCentralManager scanning to detect it")
            }

            continuation?.resume(returning: .success(()))
            continuation = nil
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == beaconCharacteristicUUID,
              let config = configuration else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }

        request.value = createGATTBeaconData(config: config)
        peripheral.respond(to: request, withResult: .success)
    }

    // MARK: - Status Display

    func showStatus() {
        guard let config = configuration else { return }
        let timestamp = DateFormatter.timestamp.string(from: Date())
        let elapsed = Int(Date().timeIntervalSince(advertisingStartTime ?? Date()))
        let status = _isEmitting ? "🟢 ACTIVE" : "🔴 INACTIVE"
        print("[\(timestamp)] Status: \(status) | Mode: \(mode.rawValue) | Elapsed: \(elapsed)s")
        print("                   UUID: \(config.uuid.uuidString) | Major: \(config.major) | Minor: \(config.minor)")
        print("")
    }
}
