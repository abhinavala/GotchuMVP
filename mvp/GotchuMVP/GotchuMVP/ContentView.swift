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
        NavigationStack { // Navigation container
            ScrollView { // Allows scrolling
                VStack(spacing: 16) { // Vertical stack with spacing
                    baseURLSection // Show server URL controls
                    loginSection // Show login controls
                    walletSection // Show wallet info
                    sessionSection // Session creation UI
                    resolveSection // Manual resolve + pay
                    bleSection // BLE controls
                } // End VStack
                .padding() // Add padding
            } // End ScrollView
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
        } // End NavigationStack
    } // End body
    
    private var paymentRequestSheetView: some View { // Payment request sheet (before accepting)
        NavigationStack { // Navigation container
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
        } // End NavigationStack
    } // End paymentRequestSheetView
    
    private var paySheetView: some View { // Pay sheet that appears after locking
        NavigationStack { // Navigation container
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
        } // End NavigationStack
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
        .onChange(of: state.activeSession) { oldValue, newValue in // When session created
            if let session = newValue { // New session exists
                ble.startAdvertising(eid: session.eid) // Auto-start advertising
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
        VStack(alignment: .leading, spacing: 8) { // Stack
            Text("BLE Scanner") // Title
                .font(.headline) // Headline style
            Text("Status: \(ble.statusText)") // Status label
                .font(.caption) // Caption font
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
