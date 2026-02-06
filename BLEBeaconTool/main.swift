//
//  main.swift
//  BLEBeaconTool
//
//  Created by 横尾 on 2026/02/05.
//

import Foundation
import CoreBluetooth
import ArgumentParser

struct BLEBeaconTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "BLE iBeacon Broadcasting and Scanning Tool",
        subcommands: [Advertise.self, Scan.self, Status.self],
        defaultSubcommand: Advertise.self
    )
}

extension BLEBeaconTool {
    struct Advertise: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Broadcast iBeacon signals"
        )
        
        @Option(name: .shortAndLong, help: "UUID for the beacon")
        var uuid: String = "92821D61-9FEE-4003-87F1-31799E12017A"
        
        @Option(name: .shortAndLong, help: "Major value (1-65535)")
        var major: UInt16 = 100
        
        @Option(name: .shortAndLong, help: "Minor value (1-65535)")
        var minor: UInt16 = 1
        
        @Option(name: .shortAndLong, help: "TX Power (-59 to 4 dBm)")
        var power: Int8 = -59
        
        @Flag(name: .shortAndLong, help: "Enable verbose output")
        var verbose = false
        
        func run() throws {
            print("🎯 BLE iBeacon Broadcaster")
            print("UUID: \(uuid)")
            print("Major: \(major), Minor: \(minor)")
            print("TX Power: \(power) dBm")
            print(String(repeating: "=", count: 50))
            
            // Create configuration
            let config: BeaconConfiguration
            do {
                config = try BeaconConfiguration(
                    uuidString: uuid,
                    major: major,
                    minor: minor,
                    txPower: power,
                    verbose: verbose
                )
            } catch {
                print("❌ Configuration Error: \(error.localizedDescription)")
                throw ExitCode.failure
            }
            
            // Use the enhanced strategy
            let strategy = EnhancediBeaconStrategy()
            print("🛠️ Strategy: \(strategy.strategyName)")
            
            // Create semaphore for async handling  
            let semaphore = DispatchSemaphore(value: 0)
            var shouldStop = false
            
            // Set up signal handling for graceful shutdown
            signal(SIGINT) { _ in
                print("\n🛑 Received interrupt signal, stopping...")
                shouldStop = true
                semaphore.signal()
            }
            
            // Check if emission is possible
            Task {
                if await strategy.canEmit() {
                    print("✅ System can emit beacons")
                    let result = await strategy.startEmission(config: config)
                    switch result {
                    case .success:
                        print("🚀 Broadcasting iBeacon...")
                        print("Press Ctrl+C to stop")
                        print("Status updates every 10 seconds...")
                        print("")
                    case .failure(let error):
                        print("❌ Emission Error: \(error.localizedDescription)")
                        semaphore.signal()
                        return
                    }
                } else {
                    print("❌ System cannot emit beacons (hardware/permissions)")
                    semaphore.signal()
                    return
                }
            }
            
            // Keep running with proper run loop for timers
            while !shouldStop {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
            }
            
            // Clean shutdown
            Task {
                await strategy.stopEmission()
                semaphore.signal()
            }
            
            // Wait a moment for cleanup
            _ = semaphore.wait(timeout: .now() + 2.0)
        }
    }
    
    struct Scan: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Scan for nearby iBeacon signals"
        )
        
        @Option(name: .shortAndLong, help: "UUID to scan for (optional)")
        var uuid: String?
        
        @Option(name: .shortAndLong, help: "Scan duration in seconds")
        var duration: Int = 30
        
        @Flag(name: .shortAndLong, help: "Enable verbose output")
        var verbose = false
        
        func run() throws {
            print("📡 BLE iBeacon Scanner")
            if let uuid = uuid {
                print("Filtering UUID: \(uuid)")
            } else {
                print("Scanning for all iBeacons")
            }
            print("Duration: \(duration) seconds")
            print(String(repeating: "=", count: 50))
            
            let scanner = BeaconScanner(
                filterUUID: uuid,
                duration: duration,
                verbose: verbose
            )
            
            scanner.startScanning()
            let semaphore = DispatchSemaphore(value: 0)
            
            // Keep running for specified duration
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(duration)) {
                scanner.stopScanning()
                semaphore.signal()
            }
            
            semaphore.wait()
        }
    }
    
    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show Bluetooth status and system information"
        )
        
        func run() throws {
            print("🔍 System Status")
            print(String(repeating: "=", count: 50))
            
            let semaphore = DispatchSemaphore(value: 0)
            let statusChecker = SystemStatusChecker()
            
            statusChecker.checkStatus {
                semaphore.signal()
            }
            
            // Add timeout to prevent hanging
            let timeoutResult = semaphore.wait(timeout: .now() + 10.0)
            
            if timeoutResult == .timedOut {
                print("\n⚠️ Status check timed out after 10 seconds")
                print("This may indicate Bluetooth system issues or insufficient permissions")
            }
        }
    }
}

// Main execution entry point
BLEBeaconTool.main()
