//
//  BLEManager.swift // File header comment
//  GotchuMVP // Project name
//
//  Created by ChatGPT on 11/19/25. // Metadata comment
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
    private let rssiThreshold: Int = -60 // dBm threshold (phones must be close)
    private let requiredSamples: Int = 4 // Need 4 out of 5 samples above threshold
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
            return // Exit early
        } // End guard
        let data = eidData(from: eid) // Convert string to data
        // Use manufacturer data for custom payload (company ID 0xFFFF for development)
        // Format: [company ID (2 bytes) + EID data (5 bytes)]
        var manufacturerData = Data() // Create data container
        manufacturerData.append(contentsOf: [0xFF, 0xFF]) // Add company ID (0xFFFF for dev)
        manufacturerData.append(data) // Append EID data
        let advertisement: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID], // Include service UUID for filtering
            CBAdvertisementDataManufacturerDataKey: manufacturerData // Include EID in manufacturer data
        ] // End advertisement dictionary
        peripheralManager.startAdvertising(advertisement) // Start broadcasting
        statusText = "Advertising \(eid)" // Update status text
    } // End startAdvertising
    
    func stopAdvertising() { // Stops advertising
        peripheralManager.stopAdvertising() // Stop peripheral manager
        advertisingEID = nil // Clear state
        statusText = "Idle" // Reset status
    } // End stopAdvertising
    
    func startScanning() { // Begins scanning for EIDs
        guard centralManager.state == .poweredOn else { // Ensure BLE ready
            statusText = "Scanner off" // Update status
            return // Exit
        } // End guard
        rssiSamples.removeAll() // Clear RSSI tracking
        readyToPayEID = nil // Clear ready EID
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) // Start scan
        statusText = "Scanning - Bring phones close together" // Update status
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
        let strongSamples = samples.filter { $0 > rssiThreshold }.count // Count samples above threshold
        if strongSamples >= requiredSamples && readyToPayEID == nil { // Passes gate and not already set
            readyToPayEID = eid // Mark as ready
            statusText = "Payment session detected!" // Update status
            let generator = UINotificationFeedbackGenerator() // Create haptic generator
            generator.notificationOccurred(.success) // Success haptic
            onEIDReady?(eid) // Trigger callback for auto-resolve
        } else if strongSamples < requiredSamples { // Not close enough
            let avgRSSI = samples.reduce(0, +) / samples.count // Calculate average
            if avgRSSI < rssiThreshold - 10 { // Very far
                statusText = "Too far - bring phones closer" // Update status
            } else if avgRSSI < rssiThreshold { // Getting closer
                statusText = "Getting closer..." // Update status
            } else { // Close but need more samples
                statusText = "Almost there..." // Update status
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
            return // Not our service, ignore
        } // End guard
        // Extract EID from manufacturer data (format: [0xFF, 0xFF] + EID bytes)
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerData.count >= 7, // Must have company ID (2 bytes) + EID (5 bytes)
           manufacturerData[0] == 0xFF && manufacturerData[1] == 0xFF { // Check company ID
            let eidData = manufacturerData.subdata(in: 2..<manufacturerData.count) // Extract EID bytes (skip first 2)
            let eid = eidData.map { String(format: "%02x", $0) }.joined() // Convert bytes to hex string
            let rssiValue = RSSI.intValue // Convert RSSI to Int
            Task { @MainActor in // Switch to main actor for UI updates
                if !discoveredEIDs.contains(eid) { // Avoid duplicates
                    discoveredEIDs.append(eid) // Append new EID
                } // End duplicate check
                checkRSSIGate(eid: eid, rssi: rssiValue) // Check if passes RSSI gate
            } // End Task
        } // End manufacturer data guard
    } // End didDiscover
} // End extension

