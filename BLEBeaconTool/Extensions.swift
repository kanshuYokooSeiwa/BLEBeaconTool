//
//  Extensions.swift
//  BLEBeaconTool
//
//  Shared extensions used across the project.
//

import Foundation
import CoreBluetooth

extension CBManagerState {
    var description: String {
        switch self {
        case .poweredOn:
            return "poweredOn"
        case .poweredOff:
            return "poweredOff"
        case .unauthorized:
            return "unauthorized"
        case .unsupported:
            return "unsupported"
        case .resetting:
            return "resetting"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown(\(rawValue))"
        }
    }
}

extension DateFormatter {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

extension String {
    func chunked(by length: Int) -> [String] {
        return stride(from: 0, to: count, by: length).map {
            let start = index(startIndex, offsetBy: $0)
            let end = index(start, offsetBy: min(length, count - $0))
            return String(self[start..<end])
        }
    }
}
