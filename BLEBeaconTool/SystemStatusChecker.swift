//
//  SystemStatusChecker.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/05.
//

import Foundation
import CoreBluetooth

class SystemStatusChecker: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    private var completion: (() -> Void)?
    
    func checkStatus(completion: @escaping () -> Void) {
        self.completion = completion
        
        print("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("App Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth Status: Powered On")
        case .poweredOff:
            print("❌ Bluetooth Status: Powered Off")
        case .unauthorized:
            print("❌ Bluetooth Status: Unauthorized")
        case .unsupported:
            print("❌ Bluetooth Status: Unsupported")
        case .unknown:
            print("❓ Bluetooth Status: Unknown")
        case .resetting:
            print("🔄 Bluetooth Status: Resetting")
        @unknown default:
            print("❓ Bluetooth Status: Unknown (\(central.state.rawValue))")
        }
        
        showPermissionStatus()
        completion?()
    }
    
    private func showPermissionStatus() {
        print("\n🔧 Troubleshooting Guide:")
        print("1. Ensure Bluetooth is enabled in System Settings")
        print("2. Grant Bluetooth permissions:")
        print("   System Settings → Privacy & Security → Bluetooth")
        print("   Enable access for this app or Terminal")
        print("3. Grant Location permissions for scanning:")
        print("   System Settings → Privacy & Security → Location Services")
        print("4. Run as admin if needed: sudo ./BLEBeaconTool")
    }
}

