//
//  SystemStatusChecker.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/05.
//

import Foundation
@preconcurrency import CoreBluetooth
import OSLog

class SystemStatusChecker: NSObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var completion: (() -> Void)?
    private let logger = Logger(subsystem: "com.blebeacon.tool", category: "status")
    private let statusQueue = DispatchQueue(label: "com.k-yokoo.status-bluetooth")
    private var centralReady = false
    private var peripheralReady = false
    
    func checkStatus(completion: @escaping () -> Void) {
        self.completion = completion
        
        print("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        print("Running as: \(getuid() == 0 ? "root" : "user")")
        print()
        
        // Test both central and peripheral capabilities
        centralManager = CBCentralManager(delegate: self, queue: statusQueue)
        peripheralManager = CBPeripheralManager(delegate: self, queue: statusQueue)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth Central: Powered On")
            logger.info("Bluetooth central powered on")
        case .poweredOff:
            print("❌ Bluetooth Central: Powered Off")
            logger.warning("Bluetooth central powered off")
        case .unauthorized:
            print("❌ Bluetooth Central: Unauthorized")
            logger.error("Bluetooth central unauthorized")
        case .unsupported:
            print("❌ Bluetooth Central: Unsupported")
            logger.error("Bluetooth central unsupported")
        case .unknown:
            print("❓ Bluetooth Central: Unknown")
            logger.info("Bluetooth central state unknown")
        case .resetting:
            print("🔄 Bluetooth Central: Resetting")
            logger.info("Bluetooth central resetting")
        @unknown default:
            print("❓ Bluetooth Central: Unknown (\(central.state.rawValue))")
            logger.warning("Unknown bluetooth central state: \(central.state.rawValue)")
        }
        
        centralReady = true
        checkCompletion()
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("✅ Bluetooth Peripheral: Powered On (advertising capable)")
        case .poweredOff:
            print("❌ Bluetooth Peripheral: Powered Off")
        case .unauthorized:
            print("❌ Bluetooth Peripheral: Unauthorized")
        case .unsupported:
            print("❌ Bluetooth Peripheral: Unsupported")
        case .unknown:
            print("❓ Bluetooth Peripheral: Unknown")
        case .resetting:
            print("🔄 Bluetooth Peripheral: Resetting")
        @unknown default:
            print("❓ Bluetooth Peripheral: Unknown (\(peripheral.state.rawValue))")
        }
        
        peripheralReady = true
        checkCompletion()
    }
    
    private func checkCompletion() {
        if centralReady && peripheralReady {
            showPermissionStatus()
            showAdvancedDiagnostics()
            completion?()
        }
    }
    
    private func showPermissionStatus() {
        print("\n🔐 Permissions:")
        print("Bluetooth Authorization: \(CBPeripheralManager.authorization == .allowedAlways ? "✅ Granted" : "❌ Denied")")
        
        print("\n🔧 Troubleshooting Guide:")
        print("1. Ensure Bluetooth is enabled in System Settings")
        print("2. Grant Bluetooth permissions:")
        print("   System Settings → Privacy & Security → Bluetooth")
        print("   Enable access for this app or Terminal")
        print("3. For beacon advertising on macOS:")
        print("   • Ensure app bundle is signed with App Sandbox & Bluetooth entitlements")
        print("   • Execute via the .app bundle: ./BLEBeaconTool.app/Contents/MacOS/BLEBeaconTool advertise")
        print("4. For scanning, grant Location permissions:")
        print("   System Settings → Privacy & Security → Location Services")
    }
    
    private func showAdvancedDiagnostics() {
        print("\n🔬 Advanced Diagnostics:")
        
        // Check system version restrictions
        let version = ProcessInfo.processInfo.operatingSystemVersion
        print("ℹ️  macOS \(version.majorVersion).\(version.minorVersion) detected")
        
        // Check process permissions
        if getuid() == 0 {
            print("✅ Running with elevated privileges")
        } else {
            print("ℹ️  Running as regular user")
        }
        
        // Check bundle ID (important for permissions)
        if let bundleId = Bundle.main.bundleIdentifier {
            print("✅ App Bundle Identifier: \(bundleId)")
        } else {
            print("⚠️  No bundle identifier - may affect permission requests")
        }
    }
}
