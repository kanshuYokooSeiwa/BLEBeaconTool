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
        
        @Option(name: .shortAndLong, help: "Major value (0-65535)")
        var major: UInt16 = 100
        
        @Option(name: .shortAndLong, help: "Minor value (0-65535)")
        var minor: UInt16 = 1
        
        @Option(name: .shortAndLong, help: "TX Power (-59 to 4 dBm)")
        var power: Int8 = -59

        @Flag(help: "Allow fallback to GATT mode when iBeacon advertising is restricted on macOS")
        var allowGattFallback = false

        @Flag(help: "Require strict iBeacon mode (fails on macOS where iBeacon advertising is restricted)")
        var strictIBeacon = false
        
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
            
            let capabilityDetector = SystemCapabilityDetector()
            var activeStrategy: (any BeaconEmissionStrategy)?
            
            // Set up signal handling for graceful shutdown
            var sigintSrc: DispatchSourceSignal?
            sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            sigintSrc?.setEventHandler {
                print("\n🛑 Received interrupt signal, stopping...")
                Task {
                    if let strategy = activeStrategy {
                        await strategy.stopEmission()
                    }
                }
                Foundation.exit(0)
            }
            sigintSrc?.resume()
            signal(SIGINT, SIG_IGN)
            
            // Resolve strategy, then start emission
            Task {
                let capabilities = await capabilityDetector.checkBluetoothCapabilities()
                let permissions = await capabilityDetector.checkPermissions()

                if !capabilities.bluetoothAvailable {
                    print("❌ Bluetooth is not available or powered on")
                    Foundation.exit(1)
                }

                if !permissions.bluetoothAuthorized {
                    let error = BeaconError.bluetoothUnauthorized
                    print("❌ Emission Error: \(error.localizedDescription)")
                    if let suggestion = error.recoverySuggestion {
                        print("💡 \(suggestion)")
                    }
                    Foundation.exit(1)
                }

                // ── Strategy cascade ──────────────────────────────────────────
                // macOS < 11  : EnhancediBeaconStrategy (standard, no restrictions)
                // macOS 11+   : PrivateKeyIBeaconStrategy first (kCBAdvDataAppleBeaconKey)
                //               └─ if rejected → GATTServiceStrategy (fallback)
                // --strict-ibeacon: fail hard if private key is also rejected
                // ─────────────────────────────────────────────────────────────

                if !capabilities.restrictionsDetected {
                    // macOS < 11: standard iBeacon path, no restrictions
                    let strategy = EnhancediBeaconStrategy()
                    activeStrategy = strategy
                    print("🛠️ Strategy: \(strategy.strategyName)")

                    guard await strategy.canEmit() else {
                        print("❌ System cannot emit beacons (hardware/permissions)")
                        Foundation.exit(1)
                    }
                    let result = await strategy.startEmission(config: config)
                    switch result {
                    case .success:
                        print("🚀 Broadcasting iBeacon...")
                        print("Press Ctrl+C to stop")
                        print("Status updates every 2 seconds...")
                        print("")
                    case .failure(let error):
                        print("❌ Emission Error: \(error.localizedDescription)")
                        if let suggestion = error.recoverySuggestion { print("💡 \(suggestion)") }
                        Foundation.exit(1)
                    }

                } else {
                    // macOS 11+: iBeacon manufacturer data is restricted.
                    // Try kCBAdvDataAppleBeaconKey (private CoreBluetooth key) first.
                    print("🔑 macOS 11+ detected — trying Private Key iBeacon (kCBAdvDataAppleBeaconKey)...")
                    let privateKeyStrategy = PrivateKeyIBeaconStrategy()
                    activeStrategy = privateKeyStrategy

                    let privateResult = await privateKeyStrategy.startEmission(config: config)
                    switch privateResult {
                    case .success:
                        // Private key accepted — a true iBeacon frame may be on air
                        print("🚀 Broadcasting via Private Key iBeacon...")
                        print("Press Ctrl+C to stop")
                        print("Status updates every 2 seconds...")
                        print("")

                    case .failure:
                        // Private key rejected by this macOS version
                        print("⚠️  kCBAdvDataAppleBeaconKey was rejected by this macOS version")

                        if strictIBeacon {
                            let error = BeaconError.advertisingRestricted
                            print("❌ Emission Error: \(error.localizedDescription)")
                            if let suggestion = error.recoverySuggestion { print("💡 \(suggestion)") }
                            Foundation.exit(1)
                        }

                        // Auto-fallback to GATT
                        print("↩️  Falling back to GATT service mode...")
                        print("ℹ️  GATT fallback is NOT detectable by CLLocationManager on iOS")
                        print("💡 Use --strict-ibeacon to fail instead of falling back")
                        let gattStrategy = GATTServiceStrategy()
                        activeStrategy = gattStrategy

                        let gattResult = await gattStrategy.startEmission(config: config)
                        switch gattResult {
                        case .success:
                            print("🚀 Broadcasting GATT fallback...")
                            print("Press Ctrl+C to stop")
                            print("Status updates every 2 seconds...")
                            print("")
                        case .failure(let gattError):
                            print("❌ GATT fallback also failed: \(gattError.localizedDescription)")
                            if let suggestion = gattError.recoverySuggestion { print("💡 \(suggestion)") }
                            Foundation.exit(1)
                        }
                    }
                }
            }
            
            // Keep running until interrupted
            RunLoop.main.run()
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

        @Flag(help: "Dump raw advertisement data from every BLE peripheral (diagnostic mode)")
        var dumpAds = false
        
        func run() throws {
            print("📡 BLE iBeacon Scanner")
            if let uuid = uuid {
                print("Filtering UUID: \(uuid)")
            } else {
                print("Scanning for all iBeacons")
            }
            if dumpAds {
                print("🔍 Diagnostic mode: dumping raw advertisement data from all peripherals")
            }
            print("Duration: \(duration) seconds")
            print(String(repeating: "=", count: 50))
            
            let scanner = BeaconScanner(
                filterUUID: uuid,
                duration: duration,
                verbose: verbose,
                dumpAds: dumpAds
            )
            
            scanner.startScanning()
            
            // Schedule stop after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(duration)) {
                scanner.stopScanning()
                Foundation.exit(0)
            }
            
            // Keep the run loop spinning so CBCentralManager delegate callbacks are delivered
            RunLoop.main.run()
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
