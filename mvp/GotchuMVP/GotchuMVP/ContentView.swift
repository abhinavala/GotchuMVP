//
//  ContentView.swift
//  GotchuMVP
//
//  Created by Abhinav Ala on 11/15/25.
//

import SwiftUI // Import SwiftUI

struct ContentView: View { // Root view
    @EnvironmentObject var state: AppState // Access shared state
    @EnvironmentObject var ble: BLEManager // Access BLE manager
    
    var body: some View { // View body
        NavigationView { // Navigation container (iOS 15 compatible)
            ScrollView { // Allows scrolling
                VStack(spacing: 16) { // Vertical stack with spacing
                    baseURLSection // Show server URL controls
                    loginSection // Show login controls
                    walletSection // Show wallet info
                    sessionSection // Session creation UI
                    resolveSection // Manual resolve + pay
                    sendMoneySection // Send money (push payment)
                    pendingOffersSection // Pending offers (receiver)
                    bleSection // BLE controls
                } // End VStack
                .padding() // Add padding
            } // End ScrollView
            .onChange(of: state.userID) { newValue in // When user logs in (iOS 15 compatible)
                if let userID = newValue, state.autoAdvertiseAvailability { // User logged in and auto-advertise enabled
                    ble.startAdvertisingAvailability(userID: userID) // Auto-start advertising
                } else if newValue == nil { // User logged out
                    state.stopOfferPolling() // Stop polling
                    ble.stopAdvertising() // Stop advertising
                } // End if
            } // End onChange
            .navigationTitle("Gotchu Dev Panel") // Title text
            .alert("Error", isPresented: Binding(get: { state.lastError != nil }, set: { _ in state.lastError = nil })) { // Error alert binding
                Button("OK", role: .cancel) {} // Dismiss button
            } message: { // Alert message builder
                Text(state.lastError ?? "") // Show error text
            } // End alert
            .overlay(loadingOverlay) // Show loading overlay
            .sheet(isPresented: $state.showPaymentRequestSheet) { // Show payment request sheet (before locking)
                paymentRequestSheetView // Payment request content
            } // End sheet
            .sheet(isPresented: $state.showPaySheet) { // Show pay sheet when locked
                paySheetView // Pay sheet content
            } // End sheet
            .sheet(isPresented: $state.showSendMoneySheet) { // Show send money sheet
                sendMoneySheetView // Send money content
            } // End sheet
            .sheet(isPresented: $state.showPendingOffersSheet) { // Show pending offers sheet
                pendingOffersSheetView // Pending offers content
            } // End sheet
            .sheet(isPresented: $state.showPendingOfferPopup) { // Show pending offer popup
                pendingOfferPopupView // Pending offer popup content
            } // End sheet
            .sheet(isPresented: $state.showAcceptedOfferSheet) { // Show accepted offer sheet (sender completes payment)
                acceptedOfferSheetView // Accepted offer content
            } // End sheet
        } // End NavigationView
    } // End body
    
    private var paymentRequestSheetView: some View { // Payment request sheet (before accepting)
        NavigationView { // Navigation container
            VStack(spacing: 24) { // Main content stack
                if let request = state.pendingPaymentRequest { // Show payment request
                    VStack(spacing: 16) { // Info stack
                        Text("Payment Request") // Title
                            .font(.title2) // Large title
                            .fontWeight(.bold) // Bold weight
                        Text("$\(Double(request.amount_cents) / 100, specifier: "%.2f")") // Amount
                            .font(.system(size: 48, weight: .bold)) // Large amount
                            .foregroundColor(.blue) // Blue color
                        Text("From: \(request.payee_display.name)") // Payee name
                            .font(.headline) // Headline font
                            .foregroundColor(.secondary) // Secondary color
                        Text("Bring phones close together to receive this request") // Instruction
                            .font(.caption) // Caption font
                            .foregroundColor(.secondary) // Secondary color
                            .multilineTextAlignment(.center) // Center alignment
                    } // End VStack
                    .padding(.top, 40) // Top padding
                    
                    VStack(spacing: 12) { // Button stack
                        Button { // Accept request button (locks session)
                            Task { await state.acceptPaymentRequest() } // Accept and lock
                        } label: { // Button label
                            Text("Accept Request") // Button text
                                .font(.headline) // Headline font
                                .frame(maxWidth: .infinity) // Full width
                                .padding() // Padding
                        } // End button label
                        .buttonStyle(.borderedProminent) // Prominent style
                        .disabled(state.isLoading) // Disable while loading
                        
                        Button("Decline") { // Decline button
                            state.showPaymentRequestSheet = false // Dismiss sheet
                            state.pendingPaymentRequest = nil // Clear request
                            ble.readyToPayEID = nil // Clear ready EID so it can be detected again
                        } // End button
                        .buttonStyle(.bordered) // Bordered style
                    } // End VStack
                    .padding(.horizontal) // Horizontal padding
                } else { // No request
                    Text("Loading...") // Placeholder
                } // End if
            } // End VStack
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Full size
            .navigationTitle("Payment Request") // Sheet title
            .navigationBarTitleDisplayMode(.inline) // Inline title
            .toolbar { // Toolbar
                ToolbarItem(placement: .navigationBarTrailing) { // Trailing item
                    Button("Close") { // Close button
                        state.showPaymentRequestSheet = false // Dismiss sheet
                        state.pendingPaymentRequest = nil // Clear request
                        ble.readyToPayEID = nil // Clear ready EID so it can be detected again
                    } // End button
                } // End toolbar item
            } // End toolbar
        } // End NavigationView
    } // End paymentRequestSheetView
    
    private var paySheetView: some View { // Pay sheet that appears after locking
        NavigationView { // Navigation container
            VStack(spacing: 24) { // Main content stack
                if let result = state.resolveResult { // Show locked session
                    VStack(spacing: 20) { // Info stack
                        if state.sessionLocked { // Show locked confirmation
                            HStack { // Lock indicator
                                Image(systemName: "lock.fill") // Lock icon
                                    .foregroundColor(.green) // Green color
                                Text("Session Locked") // Lock text
                                    .font(.headline) // Headline font
                                    .foregroundColor(.green) // Green color
                            } // End HStack
                            Text("You can move phones apart now") // Instruction
                                .font(.caption) // Caption font
                                .foregroundColor(.secondary) // Secondary color
                        } // End if
                        
                        VStack(spacing: 16) { // Payment details
                            Text("Confirm Payment") // Title
                                .font(.title2) // Large title
                                .fontWeight(.bold) // Bold weight
                            Text("$\(Double(result.amount_cents) / 100, specifier: "%.2f")") // Amount
                                .font(.system(size: 48, weight: .bold)) // Large amount
                                .foregroundColor(.blue) // Blue color
                            VStack(spacing: 8) { // Details stack
                                Text("Pay to: \(result.payee_display.name)") // Payee name
                                    .font(.headline) // Headline font
                                if let wallet = state.wallet { // Show current balance
                                    Text("Your balance: $\(Double(wallet.available_cents) / 100, specifier: "%.2f")") // Balance text
                                        .font(.subheadline) // Subheadline font
                                        .foregroundColor(.secondary) // Secondary color
                                } // End if
                            } // End VStack
                        } // End VStack
                    } // End VStack
                    .padding(.top, 40) // Top padding
                    
                    VStack(spacing: 12) { // Button stack
                        Button { // Confirm payment button
                            Task { await state.sendPayment() } // Execute payment
                        } label: { // Button label
                            Text("Confirm & Pay") // Button text
                                .font(.headline) // Headline font
                                .frame(maxWidth: .infinity) // Full width
                                .padding() // Padding
                        } // End button label
                        .buttonStyle(.borderedProminent) // Prominent style
                        .disabled(state.isLoading) // Disable while loading
                        
                        Button("Cancel") { // Cancel button
                            state.showPaySheet = false // Dismiss sheet
                            state.resolveResult = nil // Clear resolved state
                            state.sessionLocked = false // Clear lock flag
                        } // End button
                        .buttonStyle(.bordered) // Bordered style
                    } // End VStack
                    .padding(.horizontal) // Horizontal padding
                } else { // No resolved session
                    Text("Loading...") // Placeholder
                } // End if
            } // End VStack
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Full size
            .navigationTitle("Confirm Payment") // Sheet title
            .navigationBarTitleDisplayMode(.inline) // Inline title
            .toolbar { // Toolbar
                ToolbarItem(placement: .navigationBarTrailing) { // Trailing item
                    Button("Close") { // Close button
                        state.showPaySheet = false // Dismiss sheet
                        state.resolveResult = nil // Clear resolved state
                        state.sessionLocked = false // Clear lock flag
                    } // End button
                } // End toolbar item
            } // End toolbar
        } // End NavigationView
    } // End paySheetView
    
    private var baseURLSection: some View { // Section for base URL
        VStack(alignment: .leading, spacing: 8) { // Stack for controls
            Text("Server Base URL") // Label text
                .font(.headline) // Headline style
            TextField("http://localhost:3001", text: $state.baseURLString) // Editable URL field
                .textContentType(.URL) // Suggest URL keyboard
                .keyboardType(.URL) // URL keyboard type
                .textInputAutocapitalization(.never) // Disable caps
                .autocorrectionDisabled() // Disable autocorrect
                .textFieldStyle(.roundedBorder) // Rounded style
        } // End VStack
        .frame(maxWidth: .infinity, alignment: .leading) // Stretch width
        .padding() // Inner padding
        .background(Color(.secondarySystemBackground)) // Background color
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Rounded corners
    } // End baseURLSection
    
    private var loginSection: some View { // Login controls
        VStack(alignment: .leading, spacing: 8) { // Stack layout
            Text("Development Login") // Section title
                .font(.headline) // Headline styling
            TextField("email@example.com", text: $state.email) // Email input
                .keyboardType(.emailAddress) // Email keyboard
                .textInputAutocapitalization(.never) // Lowercase input
                .autocorrectionDisabled() // Disable autocorrect
                .textFieldStyle(.roundedBorder) // Rounded style
            Button("Sign In") { Task { await state.login() } } // Login button
                .buttonStyle(.borderedProminent) // Prominent style
            if let token = state.authToken { // Show token snippet if logged in
                Text("Token: \(token.prefix(12))…") // Display partial token
                    .font(.caption) // Smaller font
                    .foregroundStyle(.secondary) // Secondary color
            } // End token display
        } // End VStack
        .frame(maxWidth: .infinity, alignment: .leading) // Stretch width
        .padding() // Padding
        .background(Color(.secondarySystemBackground)) // Background color
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Rounded corners
    } // End loginSection
    
    private var walletSection: some View { // Wallet info section
        VStack(alignment: .leading, spacing: 8) { // Stack
            HStack { // Title row
                Text("Wallet") // Title text
                    .font(.headline) // Headline style
                Spacer() // Push content apart
                Button("Refresh") { Task { await state.refreshWallet() } } // Refresh button
            } // End HStack
            if let wallet = state.wallet { // Show wallet data
                Text("Balance: $\(Double(wallet.available_cents) / 100, specifier: "%.2f")") // Display balance
                    .font(.title2) // Large font
                Text("Wallet ID: \(wallet.wallet_id)") // Wallet ID text
                    .font(.caption) // Small font
                if wallet.recent.isEmpty { // Check entries
                    Text("No recent transactions") // Placeholder text
                        .font(.footnote) // Footnote font
                } else { // Show entries
                    VStack(alignment: .leading, spacing: 4) { // Entry list
                        ForEach(wallet.recent) { entry in // Iterate entries
                            HStack { // Entry row
                                Text(entry.type) // Entry type
                                Spacer() // Spacer
                                Text("\(entry.direction == "DEBIT" ? "-" : "+")$\(Double(entry.amount_cents) / 100, specifier: "%.2f")") // Amount text
                            } // End HStack
                            .font(.caption) // Entry font
                        } // End ForEach
                    } // End VStack
                } // End if
            } else { // Not logged in
                Text("Login to view wallet") // Placeholder message
                    .font(.footnote) // Footnote style
            } // End wallet display
        } // End VStack
        .frame(maxWidth: .infinity, alignment: .leading) // Stretch width
        .padding() // Padding
        .background(Color(.secondarySystemBackground)) // Background
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Rounded corners
    } // End walletSection
    
    private var sessionSection: some View { // Session creation UI
        VStack(alignment: .leading, spacing: 8) { // Stack
            Text("Request Payment") // Title
                .font(.headline) // Headline style
            TextField("Amount in dollars", text: $state.amountInput) // Amount field
                .keyboardType(.decimalPad) // Decimal keyboard
                .textFieldStyle(.roundedBorder) // Rounded style
            Button("Create Session") { Task { await state.createSession() } } // Create session button
                .buttonStyle(.borderedProminent) // Prominent style
            if let session = state.activeSession { // Show session details
                Text("SID: \(session.sid)") // Display SID
                    .font(.caption) // Caption font
                Text("EID: \(session.eid)") // Display EID
                    .font(.caption) // Caption font
                Text("Expires at: \(session.exp_at)") // Show expiration
                    .font(.caption2) // Smaller font
                if ble.advertisingEID == session.eid { // Check if advertising
                    Text("✅ Advertising - Bring phones close together") // Status text
                        .font(.caption) // Caption font
                        .foregroundColor(.green) // Green color
                    Button("Stop Advertising") { ble.stopAdvertising() } // Stop advertising
                        .tint(.red) // Red tint
                } else { // Not advertising
                    Button("Start Advertising") { ble.startAdvertising(eid: session.eid) } // Start advertising
                } // End if
            } // End session details
        } // End VStack
        .frame(maxWidth: .infinity, alignment: .leading) // Stretch width
        .padding() // Padding
        .background(Color(.secondarySystemBackground)) // Background
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Rounded corners
            .onChange(of: state.activeSession) { newValue in // When session created (iOS 15 compatible)
                if let session = newValue { // New session exists
                    // Stop user availability advertising when payment session is active (prioritize payment session)
                    if let userID = getCurrentUserID(), ble.advertisingUserID == userID { // Currently advertising availability
                        ble.stopAdvertising() // Stop user availability advertising
                    } // End if
                    ble.startAdvertising(eid: session.eid) // Auto-start advertising payment session
                } else { // Session ended (newValue is nil) - payment completed or cancelled
                    // Stop all BLE activity after payment
                    ble.stopAdvertising() // Stop advertising
                    ble.stopScanning() // Stop scanning (if payer was scanning)
                    ble.readyToPayEID = nil // Clear ready EID
                    ble.proximityPercentage = 0.0 // Reset proximity
                    print("🧹 BLE: Stopped all activity after session ended") // Debug log
                    // Resume user availability advertising if auto-advertise is enabled
                    if let userID = getCurrentUserID(), state.autoAdvertiseAvailability { // Should advertise availability
                        ble.startAdvertisingAvailability(userID: userID) // Resume advertising availability
                    } // End if
                } // End if
            } // End onChange
            .onChange(of: state.sessionLocked) { newValue in // When session lock state changes
                if !newValue && state.resolveResult == nil { // Session unlocked and no active payment
                    // Payment completed or cancelled - ensure BLE is stopped
                    ble.stopScanning() // Stop scanning
                    ble.readyToPayEID = nil // Clear ready EID
                    ble.proximityPercentage = 0.0 // Reset proximity
                    print("🧹 BLE: Stopped scanning after payment completed") // Debug log
                } // End if
            } // End onChange
    } // End sessionSection
    
    private var resolveSection: some View { // Resolve + pay UI
        VStack(alignment: .leading, spacing: 8) { // Stack
            Text("Pay Nearby Session") // Title
                .font(.headline) // Headline
            TextField("Enter EID or select from scan", text: $state.resolveInput) // EID field
                .textFieldStyle(.roundedBorder) // Rounded style
                .textInputAutocapitalization(.never) // Disable caps
                .autocorrectionDisabled() // Disable autocorrect
            Button("Resolve Session") { Task { await state.resolveCurrent() } } // Resolve button
                .buttonStyle(.bordered) // Bordered style
            if let result = state.resolveResult { // Show resolved info
                Text("Amount: $\(Double(result.amount_cents) / 100, specifier: "%.2f")") // Amount text
                Text("Payee: \(result.payee_display.name)") // Payee text
                Button("Lock & Pay") { Task { await state.sendPayment() } } // Pay button
                    .buttonStyle(.borderedProminent) // Prominent style
            } // End resolved block
        } // End VStack
        .frame(maxWidth: .infinity, alignment: .leading) // Stretch width
        .padding() // Padding
        .background(Color(.secondarySystemBackground)) // Background
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Rounded corners
    } // End resolveSection
    
    private var bleSection: some View { // BLE controls
        VStack(alignment: .leading, spacing: 12) { // Stack
            Text("BLE Scanner") // Title
                .font(.headline) // Headline style
            Text("Status: \(ble.statusText)") // Status label
                .font(.caption) // Caption font
            
            // Proximity indicator (visual feedback)
            if ble.proximityPercentage > 0.0 { // Show proximity indicator when scanning
                VStack(alignment: .leading, spacing: 4) { // Proximity stack
                    HStack { // Label row
                        Text("Proximity") // Label
                            .font(.caption) // Caption font
                            .foregroundColor(.secondary) // Secondary color
                        Spacer() // Spacer
                        Text("\(Int(ble.proximityPercentage * 100))%") // Percentage
                            .font(.caption) // Caption font
                            .fontWeight(.semibold) // Semibold weight
                            .foregroundColor(.blue) // Blue color
                    } // End HStack
                    GeometryReader { geometry in // Geometry reader for progress bar
                        ZStack(alignment: .leading) { // Progress bar container
                            RoundedRectangle(cornerRadius: 4) // Background
                                .fill(Color(.tertiarySystemFill)) // Tertiary fill
                                .frame(height: 8) // Height
                            RoundedRectangle(cornerRadius: 4) // Progress fill
                                .fill(LinearGradient( // Gradient fill
                                    gradient: Gradient(colors: [
                                        Color.blue.opacity(0.6), // Start color
                                        Color.blue // End color
                                    ]), // End gradient
                                    startPoint: .leading, // Start point
                                    endPoint: .trailing // End point
                                )) // End fill
                                .frame(width: geometry.size.width * ble.proximityPercentage, height: 8) // Width based on percentage
                                .animation(.easeInOut(duration: 0.2), value: ble.proximityPercentage) // Smooth animation
                        } // End ZStack
                    } // End GeometryReader
                    .frame(height: 8) // Fixed height
                } // End VStack
            } // End if
            
            HStack { // Button row
                Button("Start Scan") { ble.startScanning() } // Start scan button
                Button("Stop Scan") { ble.stopScanning() } // Stop scan button
                    .tint(.red) // Red tint
            } // End HStack
            if ble.discoveredEIDs.isEmpty { // Check for discoveries
                Text("No EIDs yet") // Placeholder text
                    .font(.footnote) // Footnote font
            } else { // Show list
                ForEach(ble.discoveredEIDs, id: \.self) { eid in // Iterate EIDs
                    Button { state.resolveInput = eid } label: { // Fill resolve input
                        HStack { // Row layout
                            Text(eid) // Show EID
                                .font(.caption) // Caption font
                            Spacer() // Spacer
                            if ble.currentProximityEID == eid && ble.proximityPercentage > 0.5 { // Show indicator for closest EID
                                Image(systemName: "waveform.path") // Proximity icon
                                    .foregroundColor(.blue) // Blue color
                                    .font(.caption) // Caption font
                            } // End if
                            Image(systemName: "arrow.right.circle.fill") // Icon
                        } // End HStack
                    } // End button
                    .buttonStyle(.plain) // Plain style
                } // End ForEach
            } // End conditional
        } // End VStack
        .frame(maxWidth: .infinity, alignment: .leading) // Stretch width
        .padding() // Padding
        .background(Color(.secondarySystemBackground)) // Background
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Rounded corners
    } // End bleSection
    
    private var sendMoneySection: some View { // Send money UI (push payment)
        VStack(alignment: .leading, spacing: 8) { // Stack
            Text("Send Money") // Title
                .font(.headline) // Headline style
            Button("Send Money to User") { // Open send money sheet
                Task { await state.loadUsers() } // Load users first
                state.showSendMoneySheet = true // Show sheet
            } // End button
            .buttonStyle(.borderedProminent) // Prominent style
            if !state.availableUsers.isEmpty { // Show discovered users
                Text("Available users: \(state.availableUsers.count)") // Count text
                    .font(.caption) // Caption font
            } // End if
        } // End VStack
        .frame(maxWidth: .infinity, alignment: .leading) // Stretch width
        .padding() // Padding
        .background(Color(.secondarySystemBackground)) // Background
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Rounded corners
    } // End sendMoneySection
    
    private var pendingOffersSection: some View { // Pending offers UI (receiver)
        VStack(alignment: .leading, spacing: 8) { // Stack
            Text("Payment Offers") // Title
                .font(.headline) // Headline style
            Button("View Pending Offers") { // Load and show offers
                Task { 
                    await state.loadPendingOffers() // Load offers
                    state.showPendingOffersSheet = true // Show sheet
                } // End task
            } // End button
            .buttonStyle(.bordered) // Bordered style
            if !state.pendingOffers.isEmpty { // Show count
                Text("\(state.pendingOffers.count) pending offer(s)") // Count text
                    .font(.caption) // Caption font
                    .foregroundColor(.orange) // Orange color
            } // End if
            // Advertise availability for push payments
            if let userID = getCurrentUserID() { // Check if logged in
                Toggle("Auto-advertise availability", isOn: $state.autoAdvertiseAvailability) // Toggle for auto-advertise
                    .onChange(of: state.autoAdvertiseAvailability) { newValue in // When toggle changes (iOS 15 compatible)
                        if newValue { // Enabled
                            ble.startAdvertisingAvailability(userID: userID) // Start advertising
                        } else { // Disabled
                            if ble.advertisingUserID == userID { // Currently advertising
                                ble.stopAdvertising() // Stop advertising
                            } // End if
                        } // End if
                    } // End onChange
                if ble.advertisingUserID == userID { // Check if advertising
                    Text("✅ Advertising availability - Tap to receive payments") // Status text
                        .font(.caption) // Caption font
                        .foregroundColor(.green) // Green color
                } else if !state.autoAdvertiseAvailability { // Not advertising and auto-advertise off
                    Button("Advertise Availability") { // Start advertising
                        ble.startAdvertisingAvailability(userID: userID) // Start advertising
                    } // End button
                } // End if
            } // End if
        } // End VStack
        .frame(maxWidth: .infinity, alignment: .leading) // Stretch width
        .padding() // Padding
        .background(Color(.secondarySystemBackground)) // Background
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Rounded corners
        .onAppear { // When view appears
            // Set up BLE callback for user detection
            ble.onUserReady = { userIDShort in // When user detected via BLE
                // Find matching user from available users
                if let matchingUser = state.availableUsers.first(where: { 
                    String($0.id.replacingOccurrences(of: "-", with: "").prefix(8)) == userIDShort 
                }) { // Found matching user
                    state.selectedUserID = matchingUser.id // Select user
                    state.showSendMoneySheet = true // Show send money sheet
                } else { // Not found, load users and try again
                    Task { // Async task
                        await state.loadUsers() // Load users
                        if let matchingUser = state.availableUsers.first(where: { 
                            String($0.id.replacingOccurrences(of: "-", with: "").prefix(8)) == userIDShort 
                        }) { // Found matching user
                            state.selectedUserID = matchingUser.id // Select user
                            state.showSendMoneySheet = true // Show send money sheet
                        } // End if
                    } // End task
                } // End if
            } // End callback
        } // End onAppear
    } // End pendingOffersSection
    
    private func getCurrentUserID() -> String? { // Gets current user ID from AppState
        return state.userID // Return stored user ID
    } // End getCurrentUserID
    
    private var sendMoneySheetView: some View { // Send money sheet
        NavigationView { // Navigation container
            VStack(spacing: 24) { // Main content stack
                TextField("Amount in dollars", text: $state.sendAmountInput) // Amount field
                    .keyboardType(.decimalPad) // Decimal keyboard
                    .textFieldStyle(.roundedBorder) // Rounded style
                    .padding(.horizontal) // Horizontal padding
                
                if state.availableUsers.isEmpty { // No users loaded
                    Text("Loading users...") // Placeholder
                        .foregroundColor(.secondary) // Secondary color
                } else { // Show users list
                    List(state.availableUsers) { user in // Iterate users
                        Button { // User button
                            state.selectedUserID = user.id // Select user
                        } label: { // Button label
                            HStack { // Row layout
                                VStack(alignment: .leading) { // User info
                                    Text(user.display_name) // Display name
                                        .font(.headline) // Headline font
                                    Text(user.email) // Email
                                        .font(.caption) // Caption font
                                        .foregroundColor(.secondary) // Secondary color
                                } // End VStack
                                Spacer() // Spacer
                                if state.selectedUserID == user.id { // Show selection
                                    Image(systemName: "checkmark.circle.fill") // Check icon
                                        .foregroundColor(.blue) // Blue color
                                } // End if
                            } // End HStack
                        } // End button label
                        .buttonStyle(.plain) // Plain style
                    } // End List
                } // End if
                
                Button { // Create offer button
                    Task { await state.createPaymentOffer() } // Create offer
                } label: { // Button label
                    Text("Send Payment Offer") // Button text
                        .font(.headline) // Headline font
                        .frame(maxWidth: .infinity) // Full width
                        .padding() // Padding
                } // End button label
                .buttonStyle(.borderedProminent) // Prominent style
                .disabled(state.isLoading || state.selectedUserID == nil || state.sendAmountInput.isEmpty) // Disable if invalid
                .padding(.horizontal) // Horizontal padding
            } // End VStack
            .navigationTitle("Send Money") // Sheet title
            .navigationBarTitleDisplayMode(.inline) // Inline title
            .toolbar { // Toolbar
                ToolbarItem(placement: .navigationBarTrailing) { // Trailing item
                    Button("Close") { // Close button
                        state.showSendMoneySheet = false // Dismiss sheet
                    } // End button
                } // End toolbar item
            } // End toolbar
        } // End NavigationView
    } // End sendMoneySheetView
    
    private var acceptedOfferSheetView: some View { // Accepted offer sheet (sender completes payment)
        NavigationView { // Navigation container
            VStack(spacing: 24) { // Main content stack
                if let result = state.resolveResult, state.sessionLocked { // Show accepted offer
                    VStack(spacing: 16) { // Info stack
                        Text("Offer Accepted!") // Title
                            .font(.title2) // Large title
                            .fontWeight(.bold) // Bold weight
                        Text("$\(Double(result.amount_cents) / 100, specifier: "%.2f")") // Amount
                            .font(.system(size: 48, weight: .bold)) // Large amount
                            .foregroundColor(.blue) // Blue color
                        Text("Pay to: \(result.payee_display.name)") // Payee name
                            .font(.headline) // Headline font
                        if let wallet = state.wallet { // Show current balance
                            Text("Your balance: $\(Double(wallet.available_cents) / 100, specifier: "%.2f")") // Balance text
                                .font(.subheadline) // Subheadline font
                                .foregroundColor(.secondary) // Secondary color
                        } // End if
                    } // End VStack
                    .padding(.top, 40) // Top padding
                    
                    VStack(spacing: 12) { // Button stack
                        Button { // Complete payment button
                            Task { await state.sendPayment() } // Execute payment
                        } label: { // Button label
                            Text("Complete Payment") // Button text
                                .font(.headline) // Headline font
                                .frame(maxWidth: .infinity) // Full width
                                .padding() // Padding
                        } // End button label
                        .buttonStyle(.borderedProminent) // Prominent style
                        .disabled(state.isLoading) // Disable while loading
                        
                        Button("Cancel") { // Cancel button
                            state.showAcceptedOfferSheet = false // Dismiss sheet
                            state.resolveResult = nil // Clear resolved state
                            state.sessionLocked = false // Clear lock flag
                            state.acceptedOfferSID = nil // Clear accepted offer
                        } // End button
                        .buttonStyle(.bordered) // Bordered style
                    } // End VStack
                    .padding(.horizontal) // Horizontal padding
                } else { // No offer
                    Text("Loading...") // Placeholder
                } // End if
            } // End VStack
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Full size
            .navigationTitle("Complete Payment") // Sheet title
            .navigationBarTitleDisplayMode(.inline) // Inline title
            .toolbar { // Toolbar
                ToolbarItem(placement: .navigationBarTrailing) { // Trailing item
                    Button("Close") { // Close button
                        state.showAcceptedOfferSheet = false // Dismiss sheet
                        state.resolveResult = nil // Clear resolved state
                        state.sessionLocked = false // Clear lock flag
                        state.acceptedOfferSID = nil // Clear accepted offer
                    } // End button
                } // End toolbar item
            } // End toolbar
        } // End NavigationView
    } // End acceptedOfferSheetView
    
    private var pendingOfferPopupView: some View { // Pending offer popup (automatic)
        NavigationView { // Navigation container
            VStack(spacing: 24) { // Main content stack
                if let offer = state.pendingOfferPopup { // Show offer
                    let isAccepted = state.acceptedOfferSIDForReceiver == offer.sid // Check if accepted
                    let isCompleted = state.completedOfferSID == offer.sid // Check if completed
                    
                    VStack(spacing: 16) { // Info stack
                        if isCompleted { // Payment completed
                            Image(systemName: "checkmark.circle.fill") // Success icon
                                .font(.system(size: 60)) // Large icon
                                .foregroundColor(.green) // Green color
                            Text("Payment Completed!") // Title
                                .font(.title2) // Large title
                                .fontWeight(.bold) // Bold weight
                        } else if isAccepted { // Accepted, waiting for payment
                            ProgressView() // Loading spinner
                                .scaleEffect(1.5) // Larger spinner
                            Text("Waiting for Payment...") // Title
                                .font(.title2) // Large title
                                .fontWeight(.bold) // Bold weight
                        } else { // Not accepted yet
                            Text("Payment Offer") // Title
                                .font(.title2) // Large title
                                .fontWeight(.bold) // Bold weight
                        } // End if
                        
                        Text("$\(Double(offer.amount_cents) / 100, specifier: "%.2f")") // Amount
                            .font(.system(size: 48, weight: .bold)) // Large amount
                            .foregroundColor(.blue) // Blue color
                        Text("From: \(offer.payer_display.name)") // Payer name
                            .font(.headline) // Headline font
                            .foregroundColor(.secondary) // Secondary color
                        
                        if isCompleted { // Payment completed
                            Text("Payment received successfully") // Success message
                                .font(.caption) // Caption font
                                .foregroundColor(.green) // Green color
                                .multilineTextAlignment(.center) // Center alignment
                        } else if isAccepted { // Accepted, waiting
                            Text("Offer accepted. Waiting for sender to complete payment...") // Waiting message
                                .font(.caption) // Caption font
                                .foregroundColor(.secondary) // Secondary color
                                .multilineTextAlignment(.center) // Center alignment
                        } else { // Not accepted
                            Text("wants to send you money") // Instruction
                                .font(.caption) // Caption font
                                .foregroundColor(.secondary) // Secondary color
                                .multilineTextAlignment(.center) // Center alignment
                        } // End if
                    } // End VStack
                    .padding(.top, 40) // Top padding
                    
                    if !isAccepted && !isCompleted { // Show buttons only if not accepted
                        VStack(spacing: 12) { // Button stack
                            Button { // Accept offer button
                                Task { await state.acceptPaymentOffer(sid: offer.sid) } // Accept offer
                            } label: { // Button label
                                Text("Accept Offer") // Button text
                                    .font(.headline) // Headline font
                                    .frame(maxWidth: .infinity) // Full width
                                    .padding() // Padding
                            } // End button label
                            .buttonStyle(.borderedProminent) // Prominent style
                            .disabled(state.isLoading) // Disable while loading
                            
                            Button("Decline") { // Decline button
                                state.showPendingOfferPopup = false // Dismiss popup
                                state.pendingOfferPopup = nil // Clear offer
                            } // End button
                            .buttonStyle(.bordered) // Bordered style
                        } // End VStack
                        .padding(.horizontal) // Horizontal padding
                    } else if isCompleted { // Payment completed - show done button
                        Button { // Done button
                            state.showPendingOfferPopup = false // Dismiss popup
                            state.pendingOfferPopup = nil // Clear offer
                            state.completedOfferSID = nil // Clear completed tracking
                        } label: { // Button label
                            Text("Done") // Button text
                                .font(.headline) // Headline font
                                .frame(maxWidth: .infinity) // Full width
                                .padding() // Padding
                        } // End button label
                        .buttonStyle(.borderedProminent) // Prominent style
                        .padding(.horizontal) // Horizontal padding
                    } // End if
                } else { // No offer
                    Text("Loading...") // Placeholder
                } // End if
            } // End VStack
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Full size
            .navigationTitle("Payment Offer") // Sheet title
            .navigationBarTitleDisplayMode(.inline) // Inline title
            .toolbar { // Toolbar
                ToolbarItem(placement: .navigationBarTrailing) { // Trailing item
                    if state.acceptedOfferSIDForReceiver == nil && state.completedOfferSID == nil { // Only show close if not waiting/completed
                        Button("Close") { // Close button
                            state.showPendingOfferPopup = false // Dismiss popup
                            state.pendingOfferPopup = nil // Clear offer
                        } // End button
                    } // End if
                } // End toolbar item
            } // End toolbar
        } // End NavigationView
    } // End pendingOfferPopupView
    
    private var pendingOffersSheetView: some View { // Pending offers sheet
        NavigationView { // Navigation container
            VStack(spacing: 16) { // Main content stack
                if state.pendingOffers.isEmpty { // No offers
                    Text("No pending offers") // Placeholder
                        .foregroundColor(.secondary) // Secondary color
                        .padding() // Padding
                } else { // Show offers
                    List(state.pendingOffers) { offer in // Iterate offers
                        VStack(alignment: .leading, spacing: 8) { // Offer card
                            HStack { // Header row
                                Text("$\(Double(offer.amount_cents) / 100, specifier: "%.2f")") // Amount
                                    .font(.title2) // Large font
                                    .fontWeight(.bold) // Bold weight
                                Spacer() // Spacer
                            } // End HStack
                            Text("From: \(offer.payer_display.name)") // Payer name
                                .font(.subheadline) // Subheadline font
                                .foregroundColor(.secondary) // Secondary color
                            Button { // Accept button
                                Task { await state.acceptPaymentOffer(sid: offer.sid) } // Accept offer
                            } label: { // Button label
                                Text("Accept") // Button text
                                    .frame(maxWidth: .infinity) // Full width
                            } // End button label
                            .buttonStyle(.borderedProminent) // Prominent style
                            .disabled(state.isLoading) // Disable while loading
                        } // End VStack
                        .padding(.vertical, 4) // Vertical padding
                    } // End List
                } // End if
            } // End VStack
            .navigationTitle("Payment Offers") // Sheet title
            .navigationBarTitleDisplayMode(.inline) // Inline title
            .toolbar { // Toolbar
                ToolbarItem(placement: .navigationBarTrailing) { // Trailing item
                    Button("Close") { // Close button
                        state.showPendingOffersSheet = false // Dismiss sheet
                    } // End button
                } // End toolbar item
            } // End toolbar
        } // End NavigationView
    } // End pendingOffersSheetView
    
    private var loadingOverlay: some View { // Loading overlay view
        Group { // Conditional group
            if state.isLoading { // Check loading flag
                ZStack { // Overlay stack
                    Color.black.opacity(0.3).ignoresSafeArea() // Dim background
                    ProgressView() // Spinner
                        .progressViewStyle(.circular) // Circular style
                        .tint(.white) // White color
                } // End ZStack
            } // End if
        } // End Group
    } // End loadingOverlay
} // End ContentView

#Preview {
    ContentView() // Preview content
        .environmentObject(AppState()) // Inject sample state
        .environmentObject(BLEManager()) // Inject sample BLE manager
} // End preview
