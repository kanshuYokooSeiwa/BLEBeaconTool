//
//  BeaconConfiguration.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/06.
//

import Foundation

struct BeaconConfiguration {
    let uuid: UUID
    let major: UInt16
    let minor: UInt16  
    let txPower: Int8
    let verbose: Bool
    
    init(uuidString: String, major: UInt16, minor: UInt16, txPower: Int8, verbose: Bool) throws {
        guard let uuid = UUID(uuidString: uuidString) else {
            throw BeaconError.invalidUUID(uuidString)
        }
        self.uuid = uuid
        self.major = major
        self.minor = minor
        self.txPower = txPower
        self.verbose = verbose
    }
    
    func validate() -> ValidationResult {
        var issues: [String] = []
        var warnings: [String] = []
        
        // Validate major/minor ranges
        if major == 0 {
            warnings.append("Major value of 0 may not be optimal for testing")
        }
        if minor == 0 {
            warnings.append("Minor value of 0 may not be optimal for testing")
        }
        
        // Validate TX power range
        if txPower < -127 || txPower > 20 {
            issues.append("TX Power must be between -127 and 20 dBm")
        } else if txPower > 4 {
            warnings.append("TX Power above 4 dBm may not be supported on all devices")
        }
        
        // Check for common UUID issues
        let uuidString = uuid.uuidString
        if uuidString.hasPrefix("00000000") {
            warnings.append("UUID starts with zeros - consider using a more unique identifier")
        }
        
        return issues.isEmpty ? 
            ValidationResult(isValid: true, issues: [], warnings: warnings) :
            ValidationResult.invalid(issues, warnings: warnings)
    }
    
    var localName: String {
        return String(format: "BLEBeacon-%04d-%04d", major, minor)
    }
    
    var description: String {
        return """
        Beacon Configuration:
          UUID: \(uuid.uuidString)
          Major: \(major)
          Minor: \(minor)
          TX Power: \(txPower) dBm
          Local Name: \(localName)
        """
    }
}

enum BeaconProfile {
    case development
    case testing  
    case production
    
    var configuration: BeaconConfiguration {
        switch self {
        case .development:
            return try! BeaconConfiguration(
                uuidString: "92821D61-9FEE-4003-87F1-31799E12017A",
                major: 1,
                minor: 1,
                txPower: -59,
                verbose: true
            )
        case .testing:
            return try! BeaconConfiguration(
                uuidString: "92821D61-9FEE-4003-87F1-31799E12017A", 
                major: 100,
                minor: 1,
                txPower: -59,
                verbose: false
            )
        case .production:
            return try! BeaconConfiguration(
                uuidString: "92821D61-9FEE-4003-87F1-31799E12017A",
                major: 1000,
                minor: 1,
                txPower: -59,
                verbose: false
            )
        }
    }
}