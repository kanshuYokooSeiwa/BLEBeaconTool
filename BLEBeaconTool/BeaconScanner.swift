//
//  BeaconScanner.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/05.
//

import Foundation
import CoreBluetooth

class BeaconScanner: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    private let filterUUID: String?
    private let duration: Int
    private let verbose: Bool
    private let dumpAds: Bool    // diagnostic: dump raw advertisement data from every peripheral
    private var discoveredBeacons: Set<String> = []
    private let fallbackNamePrefix = "BLEBeacon-"
    
    init(filterUUID: String?, duration: Int, verbose: Bool, dumpAds: Bool = false) {
        self.filterUUID = filterUUID?.uppercased()
        self.duration = duration
        self.verbose = verbose
        self.dumpAds = dumpAds
        super.init()
    }
    
    func startScanning() {
        print("🔄 Initializing Bluetooth Central Manager...")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func stopScanning() {
        if centralManager?.isScanning == true {
            centralManager.stopScan()
        }
        print("\n🛑 Scanning stopped")
        print("📊 Summary: Found \(discoveredBeacons.count) unique beacons")
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth powered on")
            startRawBLEScan()
        case .poweredOff:
            print("❌ Bluetooth is powered off")
            exit(1)
        case .unauthorized:
            print("❌ Bluetooth access unauthorized")
            print("💡 Grant Bluetooth permissions in System Settings")
            exit(1)
        case .unsupported:
            print("❌ Bluetooth LE scanning not supported")
            exit(1)
        case .unknown, .resetting:
            print("⏳ Bluetooth state changing...")
        @unknown default:
            print("❓ Unknown Bluetooth state")
        }
    }
    
    private func startRawBLEScan() {
        print("🔍 Starting raw BLE beacon scan...")
        
        if let filterUUID = filterUUID {
            print("🎯 Filtering for UUID: \(filterUUID)")
        } else {
            print("🎯 Scanning for all iBeacons + GATT fallback beacons")
        }
        
        print("⏰ Scanning for \(duration) seconds...")
        print(String(repeating: "-", count: 50))
        
        // Scan for all peripherals, allowing duplicates to see RSSI updates
        let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        centralManager.scanForPeripherals(withServices: nil, options: options)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        // ── Diagnostic mode: dump every peripheral's raw advertisement ──
        if dumpAds {
            dumpRawAdvertisement(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        }

        if processGATTFallbackData(advertisementData: advertisementData, rssi: RSSI, peripheral: peripheral) {
            return
        }

        // Look for manufacturer data
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return
        }

        let hexString = mfgData.map { String(format: "%02X", $0) }.joined()

        // CoreBluetooth may or may not include the 2-byte Apple company ID (4C00) prefix.
        // Case A: "4C000215..." — company ID included (typical on macOS scanner)
        // Case B: "0215..."    — company ID stripped (sometimes on iOS scanner)
        // Handle both.
        if hexString.hasPrefix("4C000215") && hexString.count >= 50 {
            processIBeaconData(hexString: hexString, rssi: RSSI, peripheral: peripheral)
        } else if hexString.hasPrefix("4C00") {
            // Contains Apple company ID but different subtype — not iBeacon, log if verbose
            if verbose {
                let timestamp = DateFormatter.timestamp.string(from: Date())
                print("[\(timestamp)] 🍎 Apple device (non-iBeacon): \(peripheral.name ?? peripheral.identifier.uuidString) MfgData: \(hexString)")
            }
        } else if hexString.hasPrefix("0215") && hexString.count >= 42 {
            // Company ID stripped by CoreBluetooth — reconstruct and process as iBeacon
            let reconstructed = "4C00" + hexString
            processIBeaconData(hexString: reconstructed, rssi: RSSI, peripheral: peripheral)
        }
    }

    /// Dumps all raw advertisement keys/values for diagnostic purposes (--dump-ads flag)
    private func dumpRawAdvertisement(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = peripheral.name ?? "(unnamed)"
        let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let mfgHex = mfgData.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") } ?? "none"
        let isApple = mfgData.map { $0.prefix(2) == Data([0x4C, 0x00]) } ?? false

        // Only print if: has manufacturer data, OR is named/service-advertised
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard mfgData != nil || !serviceUUIDs.isEmpty || peripheral.name != nil else { return }

        let timestamp = DateFormatter.timestamp.string(from: Date())
        print("[\(timestamp)] 🔍 DIAG | \(name) | RSSI: \(rssi)")
        print("           Mfg data : \(mfgHex)\(isApple ? " ← Apple" : "")")
        if !serviceUUIDs.isEmpty {
            print("           Services : \(serviceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
        }
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        if !localName.isEmpty { print("           LocalName: \(localName)") }
        print()
    }

    private func processGATTFallbackData(advertisementData: [String: Any], rssi: NSNumber, peripheral: CBPeripheral) -> Bool {
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflowServiceUUIDs = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        let allServiceUUIDs = serviceUUIDs + overflowServiceUUIDs
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""

        guard !allServiceUUIDs.isEmpty || localName.hasPrefix(fallbackNamePrefix) else {
            return false
        }

        let upperFilterUUID = filterUUID?.uppercased()
        if let upperFilterUUID {
            let hasMatchingServiceUUID = allServiceUUIDs.contains { $0.uuidString.uppercased() == upperFilterUUID }
            if !hasMatchingServiceUUID {
                return false
            }
        }

        let primaryServiceUUID = allServiceUUIDs.first?.uuidString ?? "N/A"
        let beaconID = "GATT-\(peripheral.identifier.uuidString)-\(primaryServiceUUID)"
        if !discoveredBeacons.contains(beaconID) || verbose {
            discoveredBeacons.insert(beaconID)

            let timestamp = DateFormatter.timestamp.string(from: Date())
            let proximity = estimateProximity(rssi: rssi.intValue)
            let displayName = localName.isEmpty ? "N/A" : localName

            print("[\(timestamp)] 📡 Found GATT Fallback Beacon")
            print("           Service UUID: \(primaryServiceUUID)")
            print("           Local Name: \(displayName)")
            print("           RSSI: \(rssi) dBm, Proximity: \(proximity)")

            if verbose {
                print("           Peripheral ID: \(peripheral.identifier.uuidString)")
                print("           Service UUIDs: \(allServiceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
                print("           Advertisement Keys: \(advertisementData.keys.sorted().joined(separator: ", "))")
            }
            print()
        }

        return true
    }
    
    private func processIBeaconData(hexString: String, rssi: NSNumber, peripheral: CBPeripheral) {
        // Extract components from hex string
        // 4C00 (Company) 0215 (Type/Len) [UUID 32 chars] [Major 4 chars] [Minor 4 chars] [TX 2 chars]
        let uuidHex = String(hexString.dropFirst(8).prefix(32))
        let majorHex = String(hexString.dropFirst(40).prefix(4))
        let minorHex = String(hexString.dropFirst(44).prefix(4))
        
        // Format UUID with dashes
        let formattedUUID = "\(uuidHex.prefix(8))-\(uuidHex.dropFirst(8).prefix(4))-\(uuidHex.dropFirst(12).prefix(4))-\(uuidHex.dropFirst(16).prefix(4))-\(uuidHex.suffix(12))"
        
        guard let major = Int(majorHex, radix: 16),
              let minor = Int(minorHex, radix: 16) else { return }
        
        // Apply filter if specified
        if let filterUUID = filterUUID, formattedUUID != filterUUID {
            return
        }
        
        let beaconID = "\(formattedUUID)-\(major)-\(minor)"
        let proximity = estimateProximity(rssi: rssi.intValue)
        
        // Only print new beacons or if verbose is on
        if !discoveredBeacons.contains(beaconID) || verbose {
            discoveredBeacons.insert(beaconID)
            
            let timestamp = DateFormatter.timestamp.string(from: Date())
            
            print("[\(timestamp)] 📡 Found: \(formattedUUID)")
            print("           Major: \(major), Minor: \(minor)")
            print("           RSSI: \(rssi) dBm, Proximity: \(proximity)")
            
            if verbose {
                print("           Raw Data: \(hexString)")
                print("           Peripheral ID: \(peripheral.identifier.uuidString)")
            }
            print()
        }
    }
    
    private func estimateProximity(rssi: Int) -> String {
        // Very rough estimation based on common iBeacon calibration
        if rssi == 127 || rssi == 0 { return "Unknown" }
        if rssi > -50 { return "Immediate (<1m)" }
        if rssi > -75 { return "Near (1-3m)" }
        return "Far (>3m)"
    }
}
