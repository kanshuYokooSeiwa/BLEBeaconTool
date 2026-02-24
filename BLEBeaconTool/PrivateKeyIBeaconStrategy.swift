//
//  PrivateKeyIBeaconStrategy.swift
//  BLEBeaconTool
//
//  Uses the undocumented CoreBluetooth key "kCBAdvDataAppleBeaconKey" to emit
//  a true iBeacon advertisement frame on macOS.
//
//  Background:
//    On iOS, CLBeaconRegion.peripheralData(withMeasuredPower:) returns an
//    NSDictionary that CBPeripheralManager accepts and emits as a true iBeacon.
//    Internally, that dictionary uses the private key "kCBAdvDataAppleBeaconKey".
//    Passing this key directly to startAdvertising() may work on macOS as well,
//    bypassing the silent-drop restriction on CBAdvertisementDataManufacturerDataKey.
//
//  Payload format (21 bytes — CoreBluetooth internally prepends 4C 00 02 15):
//    [0..15]  UUID bytes (big-endian)
//    [16..17] Major (big-endian)
//    [18..19] Minor (big-endian)
//    [20]     Measured TX Power (signed Int8 as UInt8 bitPattern)
//
//  NOTE: Uses a private/undocumented API key. Not suitable for App Store.
//        Safe for CLI tools and development use.
//        Confirmed working on macOS 10.9 (Mavericks).
//        Behaviour on macOS 11+ is determined at runtime via the delegate callback.
//

import Foundation
@preconcurrency import CoreBluetooth
import OSLog

class PrivateKeyIBeaconStrategy: NSObject, BeaconEmissionStrategy, CBPeripheralManagerDelegate {

    // MARK: - Private CoreBluetooth key
    // The same key used internally by CLBeaconRegion.peripheralData(withMeasuredPower:) on iOS.
    private static let beaconKey = "kCBAdvDataAppleBeaconKey"

    // MARK: - State
    private var peripheralManager: CBPeripheralManager!
    private var configuration: BeaconConfiguration?
    private var _isEmitting = false
    private let logger = Logger(subsystem: "com.blebeacon.tool", category: "privatekey-strategy")
    private var continuation: CheckedContinuation<Result<Void, BeaconError>, Never>?
    private var statusTimer: Timer?
    private let statusUpdateInterval: TimeInterval = 2.0
    private var advertisingStartTime: Date?

    var isEmitting: Bool { return _isEmitting }

    var strategyName: String { return "Private Key iBeacon Strategy (kCBAdvDataAppleBeaconKey)" }

    override init() { super.init() }

    // MARK: - BeaconEmissionStrategy

    func canEmit() async -> Bool {
        return await withCheckedContinuation { continuation in
            let testManager = CBPeripheralManager(delegate: nil, queue: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume(returning: testManager.state == .poweredOn)
            }
        }
    }

    func startEmission(config: BeaconConfiguration) async -> Result<Void, BeaconError> {
        self.configuration = config
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
            if config.verbose {
                logger.info("🔄 Initializing Private Key iBeacon strategy...")
                print("🔄 Initializing Private Key iBeacon strategy...")
            }
        }
    }

    func stopEmission() async {
        if _isEmitting {
            peripheralManager.stopAdvertising()
            _isEmitting = false
            statusTimer?.invalidate()
            statusTimer = nil
            logger.info("🛑 Stopped Private Key iBeacon advertising")
            print("🛑 Stopped Private Key iBeacon advertising")
        }
    }

    // MARK: - Payload Construction

    /// Builds the 21-byte iBeacon payload.
    /// CoreBluetooth prepends 4C 00 02 15 internally when using kCBAdvDataAppleBeaconKey.
    private func buildPayload(config: BeaconConfiguration) -> Data {
        var bytes = [UInt8](repeating: 0, count: 21)

        // UUID → 16 bytes, big-endian
        withUnsafeBytes(of: config.uuid.uuid) { ptr in
            for i in 0..<16 { bytes[i] = ptr[i] }
        }

        // Major → 2 bytes, big-endian
        bytes[16] = UInt8(config.major >> 8)
        bytes[17] = UInt8(config.major & 0xFF)

        // Minor → 2 bytes, big-endian
        bytes[18] = UInt8(config.minor >> 8)
        bytes[19] = UInt8(config.minor & 0xFF)

        // TX Power → signed Int8 as UInt8 bitPattern
        bytes[20] = UInt8(bitPattern: config.txPower)

        if config.verbose {
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("📦 iBeacon payload (21 bytes): \(hex)")
            print("   (CoreBluetooth prepends: 4C 00 02 15)")
        }

        return Data(bytes)
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            logger.info("✅ Bluetooth powered on - attempting Private Key iBeacon")
            print("✅ Bluetooth powered on - attempting Private Key iBeacon")
            guard let config = configuration else {
                continuation?.resume(returning: .failure(.invalidConfiguration("Missing configuration")))
                continuation = nil
                return
            }
            let payload = buildPayload(config: config)
            let advertisingData: [String: Any] = [
                PrivateKeyIBeaconStrategy.beaconKey: payload
            ]
            peripheral.startAdvertising(advertisingData)

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

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard let continuation = self.continuation,
              let config = self.configuration else { return }

        if let error = error {
            // kCBAdvDataAppleBeaconKey was rejected by this macOS version
            logger.error("❌ Private Key iBeacon rejected: \(error.localizedDescription)")
            print("❌ Private Key iBeacon rejected: \(error.localizedDescription)")
            continuation.resume(returning: .failure(.advertisingFailed(error.localizedDescription)))
            self.continuation = nil
        } else {
            // CoreBluetooth accepted the private key
            _isEmitting = true
            advertisingStartTime = Date()
            logger.info("✅ Private Key iBeacon started - true iBeacon frame may be active!")
            print("✅ Private Key iBeacon started!")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("   UUID  : \(config.uuid.uuidString)")
            print("   Major : \(config.major)")
            print("   Minor : \(config.minor)")
            print("   Power : \(config.txPower) dBm")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔬 IMPORTANT: Verify detection with iOS CLLocationManager")
            print("   If detected → true iBeacon is working on this macOS!")
            print("   If not detected → macOS is still dropping the frame silently")

            startPeriodicStatusUpdates()
            continuation.resume(returning: .success(()))
            self.continuation = nil
        }
    }

    // MARK: - Status Timer

    private func startPeriodicStatusUpdates() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: statusUpdateInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.showStatus() }
        }
        if let statusTimer {
            RunLoop.current.add(statusTimer, forMode: .common)
        }
    }

    private func showStatus() {
        guard let config = configuration else { return }
        let timestamp = DateFormatter.timestamp.string(from: Date())
        let elapsed = Int(Date().timeIntervalSince(advertisingStartTime ?? Date()))
        let status = _isEmitting ? "🟢 ACTIVE" : "🔴 INACTIVE"
        print("[\(timestamp)] Status: \(status) | Mode: Private Key iBeacon | Elapsed: \(elapsed)s")
        print("                   UUID: \(config.uuid.uuidString) | Major: \(config.major) | Minor: \(config.minor)")
        print("")
    }
}
