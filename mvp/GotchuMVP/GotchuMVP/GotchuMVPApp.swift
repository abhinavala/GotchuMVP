//
//  GotchuMVPApp.swift
//  GotchuMVP
//
//  Created by Abhinav Ala on 11/15/25.
//

import SwiftUI // Import SwiftUI framework

@main
struct GotchuMVPApp: App { // Application entry point
    @StateObject private var appState = AppState() // Shared state object
    @StateObject private var bleManager = BLEManager() // Shared BLE manager
    
    init() { // App initialization
        // Wire up auto-resolve callback when EID passes RSSI gate
        Task { @MainActor in // Ensure main thread
            // Note: We'll set this after objects are created
        } // End task
    } // End init
    
    var body: some Scene { // Scene builder
        WindowGroup { // Primary window
            ContentView() // Root view
                .environmentObject(appState) // Inject app state
                .environmentObject(bleManager) // Inject BLE manager
                .onAppear { // When view appears
                    // Wire up auto-resolve callback
                    bleManager.onEIDReady = { eid in // When EID passes RSSI gate
                        Task { @MainActor in // Async task on main thread
                            // Only resolve if no pending request (avoid duplicates)
                            // But allow retry if request was dismissed (pendingPaymentRequest is nil)
                            if appState.pendingPaymentRequest == nil && !appState.showPaymentRequestSheet { // Check no existing request and sheet not showing
                                print("📱 Auto-resolving EID: \(eid)") // Debug log
                                await appState.resolveEID(eid) // Auto-resolve the EID (shows payment request)
                            } else { // Request already showing or pending
                                print("📱 Skipping auto-resolve - request already showing or pending") // Debug log
                            } // End if
                        } // End task
                    } // End callback
                } // End onAppear
        } // End WindowGroup
    } // End body
} // End App struct
