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
    @Published var discoveredUsers: [String] = [] // List of nearby available users (user IDs)
    @Published var advertisingUserID: String? // Currently advertised user ID (for availability)
    @Published var readyToSendUserID: String? // User ID that passed RSSI gate (ready to send payment)
    @Published var proximityPercentage: Double = 0.0 // Proximity indicator (0.0 to 1.0) for visual feedback
    @Published var currentProximityEID: String? // EID currently being tracked for proximity
    
    private nonisolated(unsafe) let serviceUUID = CBUUID(string: "0000FEED-0000-1000-8000-00805F9B34FB") // Gotchu service UUID (nonisolated for CoreBluetooth)
    private var peripheralManager: CBPeripheralManager! // Handles advertising
    private var centralManager: CBCentralManager! // Handles scanning
    
    // Enhanced RSSI tracking for tap-to-target
    private var rssiSamples: [String: [Int]] = [:] // Track RSSI samples per EID/userID
    private var rssiSmoothed: [String: Double] = [:] // Exponential moving average per device
    private var rssiVariance: [String: Double] = [:] // Signal stability tracking
    
    // Adaptive thresholds
    private let discoveryThreshold: Int = -60 // dBm threshold for initial discovery (relaxed)
    private let baseRSSIThreshold: Int = -40 // dBm threshold base (phones must be tapped together)
    private let minAverageRSSI: Int = -35 // Minimum average RSSI required (very strict - phones must be touching)
    private let requiredSamples: Int = 5 // Need all 5 samples above threshold (strict)
    private let sampleWindow: Int = 8 // Increased window for better smoothing (was 5)
    private let smoothingAlpha: Double = 0.3 // Exponential moving average factor (0.0-1.0, higher = more responsive)
    private let stabilityThreshold: Double = 5.0 // Variance threshold for signal stability (lower = more stable)
    
    // Haptic feedback tracking
    private var lastHapticProximity: [String: Double] = [:] // Track last haptic trigger per device
    
    var onEIDReady: ((String) -> Void)? // Callback when EID passes RSSI gate
    var onUserReady: ((String) -> Void)? // Callback when user ID passes RSSI gate (for push payments)
    
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
        advertisingUserID = nil // Clear user ID state
        statusText = "Idle" // Reset status
    } // End stopAdvertising
    
    func startAdvertisingAvailability(userID: String) { // Begins advertising user availability
        advertisingUserID = userID // Remember current user ID
        guard peripheralManager.state == .poweredOn else { // Ensure BLE ready
            statusText = "BLE off" // Update status
            print("❌ BLE: Cannot advertise - BLE not powered on") // Debug log
            return // Exit early
        } // End guard
        print("📡 BLE: Starting to advertise availability for userID=\(userID)") // Debug log
        // Use local name to carry user ID (format: "AVAIL" + first 8 chars of UUID without dashes)
        let userIDShort = String(userID.replacingOccurrences(of: "-", with: "").prefix(8)) // Get first 8 chars
        let localName = "AVAIL\(userIDShort)" // Create local name with user ID
        let advertisement: [String: Any] = [
            CBAdvertisementDataLocalNameKey: localName, // Include user ID in local name
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID] // Include service UUID for filtering
        ] // End advertisement dictionary
        peripheralManager.startAdvertising(advertisement) // Start broadcasting
        statusText = "Advertising availability" // Update status text
        print("✅ BLE: Advertising availability started, localName=\(localName)") // Debug log
    } // End startAdvertisingAvailability
    
    func startScanning() { // Begins scanning for EIDs
        guard centralManager.state == .poweredOn else { // Ensure BLE ready
            statusText = "Scanner off" // Update status
            print("❌ BLE: Cannot scan - BLE not powered on") // Debug log
            return // Exit
        } // End guard
        rssiSamples.removeAll() // Clear RSSI tracking
        rssiSmoothed.removeAll() // Clear smoothed values
        rssiVariance.removeAll() // Clear variance tracking
        lastHapticProximity.removeAll() // Clear haptic tracking
        readyToPayEID = nil // Clear ready EID
        readyToSendUserID = nil // Clear ready user ID
        discoveredUsers.removeAll() // Clear discovered users
        proximityPercentage = 0.0 // Reset proximity
        currentProximityEID = nil // Clear current proximity tracking
        print("🔍 BLE: Starting enhanced scan with adaptive thresholds") // Debug log
        // Scan without service filter to get manufacturer data, we'll filter manually
        // Allow duplicates for faster sampling when phones are close
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ]) // Start scan without filtering
        statusText = "Scanning - Bring phones close together" // Update status
        print("✅ BLE: Enhanced scan started") // Debug log
    } // End startScanning
    
    func stopScanning() { // Stops scanning
        centralManager.stopScan() // Stop scan
        rssiSamples.removeAll() // Clear RSSI tracking
        rssiSmoothed.removeAll() // Clear smoothed values
        rssiVariance.removeAll() // Clear variance tracking
        lastHapticProximity.removeAll() // Clear haptic tracking
        readyToPayEID = nil // Clear ready EID
        readyToSendUserID = nil // Clear ready user ID
        discoveredUsers.removeAll() // Clear discovered users
        proximityPercentage = 0.0 // Reset proximity
        currentProximityEID = nil // Clear current proximity tracking
        statusText = "Idle" // Reset status
    } // End stopScanning
    
    private func checkRSSIGate(identifier: String, rssi: Int, isUserID: Bool = false) { // Enhanced RSSI gate with adaptive thresholds and smoothing
        // Initialize tracking structures
        if rssiSamples[identifier] == nil { // Initialize if first sample
            rssiSamples[identifier] = [] // Create empty array
            rssiSmoothed[identifier] = Double(rssi) // Initialize smoothed value
            rssiVariance[identifier] = 0.0 // Initialize variance
        } // End if
        
        // Add new RSSI sample
        rssiSamples[identifier]?.append(rssi) // Add new RSSI sample
        if rssiSamples[identifier]!.count > sampleWindow { // Keep only last N samples
            rssiSamples[identifier]?.removeFirst() // Remove oldest sample
        } // End if
        
        // Calculate exponential moving average for smoothing
        let currentSmoothed = rssiSmoothed[identifier] ?? Double(rssi) // Get current smoothed value
        let newSmoothed = smoothingAlpha * Double(rssi) + (1.0 - smoothingAlpha) * currentSmoothed // Exponential moving average
        rssiSmoothed[identifier] = newSmoothed // Update smoothed value
        
        // Calculate variance for signal stability
        let samples = rssiSamples[identifier]! // Get current samples
        if samples.count >= 3 { // Need at least 3 samples for variance
            let avg = Double(samples.reduce(0, +)) / Double(samples.count) // Calculate average
            let variance = samples.map { pow(Double($0) - avg, 2) }.reduce(0, +) / Double(samples.count) // Calculate variance
            rssiVariance[identifier] = variance // Store variance
        } // End if
        
        // Adaptive threshold based on signal stability
        let variance = rssiVariance[identifier] ?? 100.0 // Get variance (default high if unknown)
        let isStable = variance < stabilityThreshold // Check if signal is stable
        let adaptiveThreshold = isStable ? baseRSSIThreshold - 2 : baseRSSIThreshold // Stricter threshold when stable (phones aren't moving)
        
        // Use smoothed RSSI for calculations (reduces noise)
        let smoothedRSSIInt = Int(newSmoothed.rounded()) // Convert to Int
        
        // Calculate proximity percentage for visual feedback (0.0 to 1.0)
        // Map RSSI from discoveryThreshold (-60) to minAverageRSSI (-35) to 0.0 to 1.0
        let proximityRange = Double(discoveryThreshold - minAverageRSSI) // Range: 25 dBm
        let currentDistance = Double(discoveryThreshold - smoothedRSSIInt) // Distance from discovery threshold
        let proximity = min(max(currentDistance / proximityRange, 0.0), 1.0) // Clamp between 0.0 and 1.0
        proximityPercentage = proximity // Update published property
        
        // Track which EID we're showing proximity for (prioritize payment EIDs)
        if !isUserID && (currentProximityEID == nil || currentProximityEID == identifier) { // Payment EID
            currentProximityEID = identifier // Update current proximity tracking
        } // End if
        
        // Progressive haptic feedback as phones get closer
        let lastHaptic = lastHapticProximity[identifier] ?? 0.0 // Get last haptic proximity
        if proximity > 0.3 && proximity > lastHaptic + 0.15 { // Trigger haptic every 15% increase
            let generator = UIImpactFeedbackGenerator(style: .light) // Light haptic for getting closer
            generator.impactOccurred() // Trigger haptic
            lastHapticProximity[identifier] = proximity // Update last haptic proximity
        } // End if
        
        guard samples.count >= requiredSamples else { // Need minimum samples before checking
            updateProximityStatus(avgRSSI: smoothedRSSIInt, threshold: adaptiveThreshold, isUserID: isUserID, proximity: proximity) // Update status based on proximity
            return // Exit early if not enough samples
        } // End guard
        
        // Count samples above adaptive threshold
        let strongSamples = samples.filter { $0 > adaptiveThreshold }.count // Count samples above threshold
        
        // Require ALL samples above threshold AND smoothed average must exceed minimum (very strict - phones must be touching)
        if strongSamples >= requiredSamples && smoothedRSSIInt > minAverageRSSI { // Passes strict gate
            if isUserID { // User availability
                // Only trigger user availability if no payment EID is ready (prioritize payment sessions)
                if readyToPayEID == nil && readyToSendUserID == nil { // No payment EID detected yet
                    readyToSendUserID = identifier // Mark as ready
                    statusText = "User detected - ready to send!" // Update status
                    let generator = UINotificationFeedbackGenerator() // Create haptic generator
                    generator.notificationOccurred(.success) // Success haptic
                    onUserReady?(identifier) // Trigger callback
                } // End if
            } else { // Payment EID (priority)
                // Payment EIDs take priority - clear user availability if payment EID detected
                if readyToSendUserID != nil { // User availability was detected first
                    readyToSendUserID = nil // Clear user availability (payment session takes priority)
                } // End if
                // Allow re-triggering if EID changed or if proximity is still high (for retry after dismissal)
                let shouldTrigger = readyToPayEID != identifier || proximity >= 0.95 // Trigger if new EID or still very close (95%+)
                if shouldTrigger { // Should trigger callback
                    let wasAlreadySet = readyToPayEID == identifier // Check if this EID was already detected
                    readyToPayEID = identifier // Mark as ready (or update if already set)
                    statusText = "Payment session detected!" // Update status
                    if !wasAlreadySet { // Only haptic on first detection
                        let generator = UINotificationFeedbackGenerator() // Create haptic generator
                        generator.notificationOccurred(.success) // Success haptic
                    } // End if
                    onEIDReady?(identifier) // Trigger callback for auto-resolve (allows retry)
                } // End if
            } // End if
        } else { // Not close enough or not all samples pass
            // Reset ready state if proximity drops significantly (phones moved apart)
            if proximity < 0.5 { // Proximity dropped below 50%
                if !isUserID && readyToPayEID == identifier { // This was the ready EID
                    readyToPayEID = nil // Clear ready state (phones moved apart)
                    print("📱 BLE: Cleared readyToPayEID - proximity dropped to \(Int(proximity * 100))%") // Debug log
                } // End if
                if isUserID && readyToSendUserID == identifier { // This was the ready user ID
                    readyToSendUserID = nil // Clear ready state
                } // End if
            } // End if
            updateProximityStatus(avgRSSI: smoothedRSSIInt, threshold: adaptiveThreshold, isUserID: isUserID, proximity: proximity, strongSamples: strongSamples) // Update status
        } // End if
    } // End checkRSSIGate
    
    private func updateProximityStatus(avgRSSI: Int, threshold: Int, isUserID: Bool, proximity: Double, strongSamples: Int? = nil) { // Updates status text based on proximity
        
        if avgRSSI < discoveryThreshold - 20 { // Very far (across room)
            statusText = isUserID ? "Too far - bring phones closer" : "Too far - bring phones closer" // Update status
        } else if avgRSSI < discoveryThreshold - 10 { // Far but detectable
            statusText = "Searching for nearby phones..." // Update status
        } else if avgRSSI < threshold - 15 { // Getting closer
            statusText = "Getting closer..." // Update status
        } else if avgRSSI < threshold - 5 { // Close but not quite there
            statusText = "Almost there... bring phones together" // Update status
        } else if avgRSSI < minAverageRSSI { // Close but not tapped together
            statusText = "Tap phones together - tops touching" // Update status
        } else if let strongSamples = strongSamples, strongSamples < requiredSamples { // Close but need more consistent samples
            statusText = "Hold phones together firmly" // Update status
        } else { // Edge case
            statusText = "Tap phones together" // Update status
        } // End branches
    } // End updateProximityStatus
    
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
        // Extract EID or user ID from local name
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            let rssiValue = RSSI.intValue // Convert RSSI to Int
            if localName.hasPrefix("GOTCHU"), localName.count == 16 { // Payment EID format: "GOTCHU" (6) + EID (10) = 16 chars
                let eid = String(localName.dropFirst(6)) // Extract EID (skip "GOTCHU" prefix)
                print("✅ BLE: Found EID=\(eid), RSSI=\(rssiValue), localName=\(localName)") // Debug log
                Task { @MainActor in // Switch to main actor for UI updates
                    if !discoveredEIDs.contains(eid) { // Avoid duplicates
                        discoveredEIDs.append(eid) // Append new EID
                        print("📱 Added EID to discovered list: \(eid)") // Debug log
                    } // End duplicate check
                    checkRSSIGate(identifier: eid, rssi: rssiValue, isUserID: false) // Check if passes RSSI gate
                } // End Task
            } else if localName.hasPrefix("AVAIL"), localName.count == 13 { // User availability format: "AVAIL" (5) + userID (8) = 13 chars
                let userIDShort = String(localName.dropFirst(5)) // Extract user ID short (8 chars)
                print("✅ BLE: Found available user=\(userIDShort), RSSI=\(rssiValue), localName=\(localName)") // Debug log
                Task { @MainActor in // Switch to main actor for UI updates
                    if !discoveredUsers.contains(userIDShort) { // Avoid duplicates
                        discoveredUsers.append(userIDShort) // Append new user ID
                        print("📱 Added user to discovered list: \(userIDShort)") // Debug log
                    } // End duplicate check
                    checkRSSIGate(identifier: userIDShort, rssi: rssiValue, isUserID: true) // Check if passes RSSI gate
                } // End Task
            } else { // Unknown format
                print("❌ BLE: Unknown local name format (localName=\(localName), count=\(localName.count))") // Debug log
            } // End format check
        } else { // Local name missing
            print("❌ BLE: Local name missing") // Debug log
        } // End local name guard
    } // End didDiscover
} // End extension

