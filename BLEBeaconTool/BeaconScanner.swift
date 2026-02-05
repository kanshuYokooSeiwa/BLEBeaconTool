//
//  BeaconScanner.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/05.
//

import Foundation
import CoreBluetooth
import CoreLocation

class BeaconScanner: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let filterUUID: String?
    private let duration: Int
    private let verbose: Bool
    private var discoveredBeacons: Set<String> = []
    private var constraint: CLBeaconIdentityConstraint?
    
    init(filterUUID: String?, duration: Int, verbose: Bool) {
        self.filterUUID = filterUUID
        self.duration = duration
        self.verbose = verbose
        super.init()
    }
    
    func startScanning() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        
    }
    
    func stopScanning() {
        if let constraint = constraint {
            locationManager.stopRangingBeacons(satisfying: constraint)
        }
        print("\n🛑 Scanning stopped")
        print("📊 Summary: Found \(discoveredBeacons.count) unique beacons")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ Location permission granted")
            startBeaconRanging()
        case .denied, .restricted:
            print("❌ Location permission denied")
            print("💡 Grant location permissions in System Settings")
            exit(1)
        case .notDetermined:
            print("⏳ Requesting location permission...")
        @unknown default:
            print("❓ Unknown location authorization status")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        for beacon in beacons {
            let beaconID = "\(beacon.uuid.uuidString)-\(beacon.major)-\(beacon.minor)"
            
            if !discoveredBeacons.contains(beaconID) {
                discoveredBeacons.insert(beaconID)
                
                let timestamp = DateFormatter.timestamp.string(from: Date())
                let proximity = proximityDescription(beacon.proximity)
                let rssi = beacon.rssi
                
                print("[\(timestamp)] 📡 Found: \(beacon.uuid.uuidString)")
                print("           Major: \(beacon.major), Minor: \(beacon.minor)")
                print("           RSSI: \(rssi) dBm, Proximity: \(proximity)")
                print("           Accuracy: \(String(format: "%.2f", beacon.accuracy))m")
                
                if verbose {
                    print("           Raw Data: \(beaconID)")
                }
                print()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager failed: \(error.localizedDescription)")
    }
    
    private func startBeaconRanging() {
        print("🔍 Starting beacon scan...")
        
        if let filterUUID = filterUUID, let uuid = UUID(uuidString: filterUUID) {
            self.constraint = CLBeaconIdentityConstraint(uuid: uuid)
            locationManager.startRangingBeacons(satisfying: self.constraint!)
            print("🎯 Filtering for UUID: \(filterUUID)")
        } else {
            // Scan for the default test UUID if no filter specified
            let defaultUUID = UUID(uuidString: "92821D61-9FEE-4003-87F1-31799E12017A")!
            self.constraint = CLBeaconIdentityConstraint(uuid: defaultUUID)
            locationManager.startRangingBeacons(satisfying: self.constraint!)
            print("🎯 Scanning for default test UUID")
        }
        
        print("⏰ Scanning for \(duration) seconds...")
        print(String(repeating: "-", count: 50))
    }
    
    private func proximityDescription(_ proximity: CLProximity) -> String {
        switch proximity {
        case .immediate: return "Immediate (<1m)"
        case .near: return "Near (1-3m)"
        case .far: return "Far (>3m)"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}
