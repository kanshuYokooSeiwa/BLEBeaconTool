//
//  BeaconError.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/06.
//

import Foundation

enum BeaconError: Error, LocalizedError {
    case bluetoothUnavailable
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case bluetoothUnsupported
    case permissionDenied
    case advertisingRestricted
    case invalidConfiguration(String)
    case systemNotSupported
    case advertisingFailed(String)
    case invalidUUID(String)
    
    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is not available"
        case .bluetoothPoweredOff:
            return "Bluetooth is powered off"
        case .bluetoothUnauthorized:
            return "Bluetooth access is unauthorized"
        case .bluetoothUnsupported:
            return "Bluetooth LE advertising is not supported"
        case .permissionDenied:
            return "Required permissions were denied"
        case .advertisingRestricted:
            return "BLE advertising is restricted on this system"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .systemNotSupported:
            return "This system does not support BLE beacon broadcasting"
        case .advertisingFailed(let reason):
            return "Failed to start advertising: \(reason)"
        case .invalidUUID(let uuid):
            return "Invalid UUID format: \(uuid)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .bluetoothUnavailable, .bluetoothPoweredOff:
            return "Enable Bluetooth in System Settings"
        case .bluetoothUnauthorized:
            return "Grant Bluetooth permissions in System Settings → Privacy & Security → Bluetooth"
        case .bluetoothUnsupported:
            return "This device does not support Bluetooth LE advertising"
        case .permissionDenied:
            return "Grant required permissions in System Settings"
        case .advertisingRestricted:
            return "Try running with elevated privileges: sudo ./BLEBeaconTool"
        case .invalidConfiguration:
            return "Check your configuration parameters"
        case .systemNotSupported:
            return "Try running on a different macOS version or device"
        case .advertisingFailed:
            return "Check system logs for more details"
        case .invalidUUID:
            return "Use a valid UUID format (e.g., 92821D61-9FEE-4003-87F1-31799E12017A)"
        }
    }
}

struct ValidationResult {
    let isValid: Bool
    let issues: [String]
    let warnings: [String]
    
    static let valid = ValidationResult(isValid: true, issues: [], warnings: [])
    
    static func invalid(_ issues: [String], warnings: [String] = []) -> ValidationResult {
        ValidationResult(isValid: false, issues: issues, warnings: warnings)
    }
}