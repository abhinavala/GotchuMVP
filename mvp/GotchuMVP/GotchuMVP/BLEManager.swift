//
//  BLEManager.swift
//  GotchuMVP
//

import Foundation // Base types
import CoreBluetooth // BLE APIs
import UIKit // For haptic feedback

@MainActor final class BLEManager: NSObject, ObservableObject { // Handles BLE advertise/scan
    @Published var discoveredEIDs: [String] = [] // List of nearby EIDs
    @Published var advertisingEID: String? // Currently advertised EID
    @Published var statusText: String = "Idle" // Human readable status
    @Published var readyToPayEID: String? // EID that passed RSSI gate (ready for payment request)
    
    private let serviceUUID = CBUUID(string: "0000FEED-0000-1000-8000-00805F9B34FB") // Gotchu service UUID
    private var peripheralManager: CBPeripheralManager! // Handles advertising
    private var centralManager: CBCentralManager! // Handles scanning
    
    // RSSI tracking for tap-to-target
    private var rssiSamples: [String: [Int]] = [:] // Track RSSI samples per EID
    private let rssiThreshold: Int = -40 // dBm threshold (phones must be tapped together, tops touching)
    private let minAverageRSSI: Int = -35 // Minimum average RSSI required (very strict - phones must be touching)
    private let requiredSamples: Int = 5 // Need all 5 samples above threshold (strict)
    private let sampleWindow: Int = 5 // Keep last 5 samples per device
    var onEIDReady: ((String) -> Void)? // Callback when EID passes RSSI gate
    
    override init() { // Initializer
        super.init() // Call superclass init
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil) // Init peripheral manager
        centralManager = CBCentralManager(delegate: self, queue: nil) // Init central manager
    } // End init
    
    func startAdvertising(eid: String) { // Begins advertising EID
        advertisingEID = eid // Remember current EID
        guard peripheralManager.state == .poweredOn else { // Ensure BLE ready
            statusText = "BLE off" // Update status
            print("❌ BLE: Cannot advertise - BLE not powered on") // Debug log
            return // Exit early
        } // End guard
        print("📡 BLE: Starting to advertise EID=\(eid)") // Debug log
        // Use local name to carry EID (more reliable than manufacturer data on iOS)
        // Format: "GOTCHU" + EID (10 chars) = 16 chars total (iOS allows up to 29 chars)
        let localName = "GOTCHU\(eid)" // Create local name with EID
        let advertisement: [String: Any] = [
            CBAdvertisementDataLocalNameKey: localName, // Include EID in local name
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID] // Include service UUID for filtering
        ] // End advertisement dictionary
        peripheralManager.startAdvertising(advertisement) // Start broadcasting
        statusText = "Advertising \(eid)" // Update status text
        print("✅ BLE: Advertising started for EID=\(eid), localName=\(localName)") // Debug log
    } // End startAdvertising
    
    func stopAdvertising() { // Stops advertising
        peripheralManager.stopAdvertising() // Stop peripheral manager
        advertisingEID = nil // Clear state
        statusText = "Idle" // Reset status
    } // End stopAdvertising
    
    func startScanning() { // Begins scanning for EIDs
        guard centralManager.state == .poweredOn else { // Ensure BLE ready
            statusText = "Scanner off" // Update status
            print("❌ BLE: Cannot scan - BLE not powered on") // Debug log
            return // Exit
        } // End guard
        rssiSamples.removeAll() // Clear RSSI tracking
        readyToPayEID = nil // Clear ready EID
        print("🔍 BLE: Starting scan (no service filter to get manufacturer data)") // Debug log
        // Scan without service filter to get manufacturer data, we'll filter manually
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) // Start scan without filtering
        statusText = "Scanning - Bring phones close together" // Update status
        print("✅ BLE: Scan started") // Debug log
    } // End startScanning
    
    func stopScanning() { // Stops scanning
        centralManager.stopScan() // Stop scan
        rssiSamples.removeAll() // Clear RSSI tracking
        readyToPayEID = nil // Clear ready EID
        statusText = "Idle" // Reset status
    } // End stopScanning
    
    private func checkRSSIGate(eid: String, rssi: Int) { // Checks if EID passes RSSI gate
        if rssiSamples[eid] == nil { // Initialize if first sample
            rssiSamples[eid] = [] // Create empty array
        } // End if
        rssiSamples[eid]?.append(rssi) // Add new RSSI sample
        if rssiSamples[eid]!.count > sampleWindow { // Keep only last N samples
            rssiSamples[eid]?.removeFirst() // Remove oldest sample
        } // End if
        let samples = rssiSamples[eid]! // Get current samples
        let avgRSSI = samples.reduce(0, +) / samples.count // Calculate average RSSI
        guard samples.count >= requiredSamples else { // Need minimum samples before checking
            if avgRSSI < rssiThreshold - 20 { // Very far (across room)
                statusText = "Too far - bring phones closer" // Update status
            } else if avgRSSI < rssiThreshold - 10 { // Getting closer
                statusText = "Getting closer..." // Update status
            } else { // Close but need more samples
                statusText = "Almost there... tap phones together" // Update status
            } // End branches
            return // Exit early if not enough samples
        } // End guard
        let strongSamples = samples.filter { $0 > rssiThreshold }.count // Count samples above threshold
        // Require ALL samples above threshold AND average must exceed minimum (very strict - phones must be touching)
        if strongSamples >= requiredSamples && avgRSSI > minAverageRSSI && readyToPayEID == nil { // Passes strict gate and not already set
            readyToPayEID = eid // Mark as ready
            statusText = "Payment session detected!" // Update status
            let generator = UINotificationFeedbackGenerator() // Create haptic generator
            generator.notificationOccurred(.success) // Success haptic
            onEIDReady?(eid) // Trigger callback for auto-resolve
        } else { // Not close enough or not all samples pass
            if avgRSSI < rssiThreshold - 20 { // Very far (across room)
                statusText = "Too far - bring phones closer" // Update status
            } else if avgRSSI < rssiThreshold - 10 { // Getting closer
                statusText = "Getting closer..." // Update status
            } else if avgRSSI < minAverageRSSI { // Close but not tapped together
                statusText = "Tap phones together - tops touching" // Update status
            } else if strongSamples < requiredSamples { // Close but need more consistent samples
                statusText = "Hold phones together firmly" // Update status
            } else { // Edge case
                statusText = "Tap phones together" // Update status
            } // End branches
        } // End if
    } // End checkRSSIGate
    
    private func eidData(from eid: String) -> Data { // Converts hex string to Data
        var data = Data() // Mutable data container
        var temp = "" // Temp string
        for char in eid { // Iterate characters
            temp.append(char) // Append char
            if temp.count == 2 { // When pair ready
                let byte = UInt8(temp, radix: 16) ?? 0 // Parse byte
                data.append(byte) // Append to data
                temp = "" // Reset temp
            } // End if
        } // End loop
        return data // Return data
    } // End eidData
} // End BLEManager

extension BLEManager: CBPeripheralManagerDelegate { // Peripheral delegate conformance
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) { // State updates (nonisolated for CoreBluetooth)
        Task { @MainActor in // Switch to main actor for UI updates
            if peripheral.state != .poweredOn { // Check power state
                advertisingEID = nil // Clear EID if off
            } // End if
        } // End Task
    } // End state update
} // End extension

extension BLEManager: CBCentralManagerDelegate { // Central delegate conformance
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) { // State callback (nonisolated for CoreBluetooth)
        Task { @MainActor in // Switch to main actor for UI updates
            if central.state != .poweredOn { // If off
                discoveredEIDs = [] // Clear list
            } // End if
        } // End Task
    } // End state update
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) { // Handle discoveries (nonisolated for CoreBluetooth)
        // Check for our service UUID first (for filtering)
        guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
              serviceUUIDs.contains(serviceUUID) else { // Must include our service UUID
            return // Not our service, ignore silently (too many other BLE devices)
        } // End guard
        // Extract EID from local name (format: "GOTCHU" + EID)
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           localName.hasPrefix("GOTCHU"), // Check if starts with "GOTCHU"
           localName.count == 16 { // Should be "GOTCHU" (6) + EID (10) = 16 chars
            let eid = String(localName.dropFirst(6)) // Extract EID (skip "GOTCHU" prefix)
            let rssiValue = RSSI.intValue // Convert RSSI to Int
            print("✅ BLE: Found EID=\(eid), RSSI=\(rssiValue), localName=\(localName)") // Debug log
            Task { @MainActor in // Switch to main actor for UI updates
                if !discoveredEIDs.contains(eid) { // Avoid duplicates
                    discoveredEIDs.append(eid) // Append new EID
                    print("📱 Added EID to discovered list: \(eid)") // Debug log
                } // End duplicate check
                checkRSSIGate(eid: eid, rssi: rssiValue) // Check if passes RSSI gate
            } // End Task
        } else { // Local name missing or invalid format
            let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "none" // Get local name or "none"
            print("❌ BLE: Local name missing or invalid format (localName=\(localName), count=\(localName.count))") // Debug log
        } // End local name guard
    } // End didDiscover
} // End extension

