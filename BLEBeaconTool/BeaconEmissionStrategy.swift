//
//  BeaconEmissionStrategy.swift  
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/06.
//

import Foundation
@preconcurrency import CoreBluetooth

protocol BeaconEmissionStrategy {
    func canEmit() async -> Bool
    func startEmission(config: BeaconConfiguration) async -> Result<Void, BeaconError>
    func stopEmission() async
    var isEmitting: Bool { get }
    var strategyName: String { get }
}

protocol SystemCapabilityChecker {
    func checkBluetoothCapabilities() async -> SystemCapabilities
    func checkPermissions() async -> PermissionStatus
    func recommendStrategy() async -> BeaconEmissionStrategy.Type
}

struct SystemCapabilities {
    let bluetoothAvailable: Bool
    let advertisingSupported: Bool
    let peripheralModeSupported: Bool
    let macOSVersion: String
    let restrictionsDetected: Bool
    
    var canAdvertise: Bool {
        bluetoothAvailable && advertisingSupported && !restrictionsDetected
    }
}

struct PermissionStatus {
    let bluetoothAuthorized: Bool
    let locationAuthorized: Bool
    let canRequestPermissions: Bool
    
    var allGranted: Bool {
        bluetoothAuthorized && locationAuthorized
    }
}

class SystemCapabilityDetector: SystemCapabilityChecker, @unchecked Sendable {
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    
    func checkBluetoothCapabilities() async -> SystemCapabilities {
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        return await withCheckedContinuation { continuation in
            let centralManager = CBCentralManager(delegate: nil, queue: nil)
            let peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)
            
            // Wait a bit for state updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let capabilities = SystemCapabilities(
                    bluetoothAvailable: centralManager.state == .poweredOn,
                    advertisingSupported: peripheralManager.state == .poweredOn,
                    peripheralModeSupported: peripheralManager.state != .unsupported,
                    macOSVersion: macOSVersion,
                    restrictionsDetected: self.detectmacOSRestrictions(macOSVersion)
                )
                continuation.resume(returning: capabilities)
            }
        }
    }
    
    func checkPermissions() async -> PermissionStatus {
        return PermissionStatus(
            bluetoothAuthorized: CBPeripheralManager.authorization == .allowedAlways,
            locationAuthorized: true, // Location not required for advertising
            canRequestPermissions: true
        )
    }
    
    func recommendStrategy() async -> BeaconEmissionStrategy.Type {
        let capabilities = await checkBluetoothCapabilities()
        let permissions = await checkPermissions()
        
        if capabilities.canAdvertise && permissions.allGranted {
            return EnhancediBeaconStrategy.self
        } else if capabilities.bluetoothAvailable {
            return GATTServiceStrategy.self
        } else {
            return SimulatedBeaconStrategy.self
        }
    }
    
    private func detectmacOSRestrictions(_ version: String) -> Bool {
        // macOS Big Sur (11.0) and later have stricter BLE advertising restrictions
        return version.contains("11.") || version.contains("12.") || version.contains("13.") || version.contains("14.") || version.contains("15.")
    }
}