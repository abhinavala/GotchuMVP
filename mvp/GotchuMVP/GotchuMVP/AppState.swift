//
//  AppState.swift
//  GotchuMVP
//

import Foundation // Provides Combine + async features

@MainActor final class AppState: ObservableObject { // Central state container
    @Published var email: String = "" // Stores user email input
    @Published var authToken: String? // Holds JWT token
    @Published var userID: String? // Stores current user ID
    @Published var wallet: WalletResponse? // Stores wallet data
    @Published var isLoading: Bool = false // Tracks loading state
    @Published var lastError: String? // Holds latest error message
    @Published var amountInput: String = "" // Stores amount text field
    @Published var activeSession: SessionResponse? // Stores current session
    @Published var resolveInput: String = "" // Manual EID entry
    @Published var resolveResult: ResolveResponse? // Stores resolved session (after locking)
    @Published var pendingPaymentRequest: ResolveResponse? // Payment request before accepting (shows amount + payee)
    @Published var showPaymentRequestSheet: Bool = false // Controls payment request sheet visibility
    @Published var showPaySheet: Bool = false // Controls pay sheet visibility (after locking)
    @Published var sessionLocked: Bool = false // Tracks if session is locked
    @Published var availableUsers: [UserInfo] = [] // List of available users for sending money
    @Published var pendingOffers: [PaymentOffer] = [] // List of pending payment offers (for receiver)
    @Published var sendAmountInput: String = "" // Amount input for send money
    @Published var selectedUserID: String? // Selected user ID for sending money
    @Published var showSendMoneySheet: Bool = false // Controls send money sheet visibility
    @Published var showPendingOffersSheet: Bool = false // Controls pending offers sheet visibility
    @Published var autoAdvertiseAvailability: Bool = true // Auto-start advertising availability when logged in
    @Published var pendingOfferPopup: PaymentOffer? // Current offer to show in popup
    @Published var showPendingOfferPopup: Bool = false // Controls pending offer popup visibility
    @Published var acceptedOfferSID: String? // SID of offer that was accepted (for sender to complete)
    @Published var showAcceptedOfferSheet: Bool = false // Controls accepted offer sheet for sender
    @Published var acceptedOfferSIDForReceiver: String? // SID of offer receiver accepted (to track completion)
    @Published var completedOfferSID: String? // SID of offer that was completed (to show success state)
    private var paymentCompletionPollingTask: Task<Void, Never>? // Polling task for payment completion (receiver side)
    private var offerPollingTask: Task<Void, Never>? // Background polling task
    private var seenOfferIDs: Set<String> = [] // Track offers we've already shown
    private var myCreatedOffers: [String: String] = [:] // Track offers I created: [sid: eid]
    @Published var baseURLString: String = "http://Abhinavs-MacBook-Pro.local:3001" { // Editable base URL string (uses Bonjour hostname)
        didSet { // Observe changes
            print("🔗 Setting base URL: \(baseURLString)") // Debug log
            if let url = URL(string: baseURLString) { // Validate URL
                api.baseURL = url // Update API client URL
                print("✅ URL set to: \(url.absoluteString)") // Debug log
            } else { // Invalid URL
                print("❌ Invalid URL: \(baseURLString)") // Debug log
            } // End if
        } // End didSet
    } // End baseURLString property
    
    private let api = APIClient.shared // Shared API client reference

    init() { // Custom initializer
        if let url = URL(string: baseURLString) { // Validate string
            api.baseURL = url // Set API base URL
        } // End if
    } // End init
    
    func login() async { // Handles dev login flow
        guard !email.isEmpty else { // Ensure email provided
            lastError = "Enter an email" // Set validation error
            return // Exit early
        } // End guard
        isLoading = true // Start loading indicator
        do { // Begin do block
            let response = try await api.devLogin(email: email) // Call login endpoint
            authToken = response.token // Store token
            userID = response.user_id // Store user ID
            lastError = nil // Clear errors
            await refreshWallet() // Fetch wallet after login
            startOfferPolling() // Start polling for pending offers (receiver side)
            startOfferStatusPolling() // Start polling for accepted offers (sender side)
        } catch { // Handle errors
            lastError = error.localizedDescription // Save error text
        } // End catch
        isLoading = false // Stop loading indicator
    } // End login
    
    func startOfferPolling() { // Starts background polling for pending offers
        stopOfferPolling() // Stop any existing polling
        guard authToken != nil else { // Ensure logged in
            return // Exit if not logged in
        } // End guard
        offerPollingTask = Task { // Create background task
            while !Task.isCancelled { // Continue until cancelled
                do { // Begin try block
                    try await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds
                    await checkForNewOffers() // Check for new offers
                } catch { // Handle cancellation
                    break // Exit loop
                } // End catch
            } // End while
        } // End task
    } // End startOfferPolling
    
    func stopOfferPolling() { // Stops background polling
        offerPollingTask?.cancel() // Cancel task
        offerPollingTask = nil // Clear reference
    } // End stopOfferPolling
    
    private func checkForNewOffers() async { // Checks for new pending offers
        guard let token = authToken else { // Ensure logged in
            return // Exit if not logged in
        } // End guard
        do { // Begin try block
            let response = try await api.getPendingOffers(token: token) // Fetch offers
            // Check for new offers we haven't seen
            for offer in response.offers { // Iterate offers
                if !seenOfferIDs.contains(offer.sid) { // New offer found
                    seenOfferIDs.insert(offer.sid) // Mark as seen
                    pendingOfferPopup = offer // Set popup offer
                    showPendingOfferPopup = true // Show popup
                    break // Only show one at a time
                } // End if
            } // End for
            pendingOffers = response.offers // Update offers list
        } catch { // Handle errors silently (don't spam errors)
            // Silently fail - will retry on next poll
        } // End catch
    } // End checkForNewOffers
    
    func refreshWallet() async { // Loads wallet data
        guard let token = authToken else { // Ensure token exists
            return // Exit if not logged in
        } // End guard
        isLoading = true // Start loading
        do { // Begin try block
            wallet = try await api.fetchWallet(token: token) // Fetch wallet data
            lastError = nil // Clear errors
        } catch { // Handle networking errors
            lastError = error.localizedDescription // Save message
        } // End catch
        isLoading = false // Stop loading
    } // End refreshWallet
    
    func createSession() async { // Creates new payment session
        guard let token = authToken else { // Ensure token present
            lastError = "Login first" // Notify missing auth
            return // Exit early
        } // End guard
        guard let cents = centsFromDecimal(amountInput) else { // Parse amount string to cents
            lastError = "Enter amount in dollars" // Validation error
            return // Exit
        } // End guard
        isLoading = true // Start loading
        do { // Begin try block
            activeSession = try await api.createSession(amount: cents, token: token) // Create session
            lastError = nil // Clear errors
            // Note: Auto-advertising will be handled by ContentView observing activeSession
        } catch { // Handle errors
            if let apiError = error as? APIError { // Check if it's an API error
                lastError = apiError.error // Use the server error message
            } else { // Fallback to localized description
                lastError = error.localizedDescription // Use system error message
            } // End if
        } // End catch
        isLoading = false // Stop loading
    } // End createSession
    
    func resolveCurrent() async { // Resolves typed EID
        guard !resolveInput.isEmpty else { // Ensure EID provided
            lastError = "Enter EID" // Validation error
            return // Exit
        } // End guard
        await resolveEID(resolveInput) // Call shared resolve logic
    } // End resolveCurrent
    
    func resolveEID(_ eid: String) async { // Resolves EID (used by auto-resolve, shows payment request)
        isLoading = true // Start spinner
        do { // Begin try block
            let resolved = try await api.resolve(eid: eid) // Call resolve
            pendingPaymentRequest = resolved // Store as pending request
            lastError = nil // Clear errors
            showPaymentRequestSheet = true // Show payment request sheet
        } catch { // Handle errors
            lastError = error.localizedDescription // Save error text
            showPaymentRequestSheet = false // Don't show sheet on error
        } // End catch
        isLoading = false // Stop spinner
    } // End resolveEID
    
    func acceptPaymentRequest() async { // Accepts payment request and locks session
        guard let token = authToken else { // Ensure logged in
            lastError = "Login first" // Notify user
            return // Exit
        } // End guard
        guard let request = pendingPaymentRequest else { // Ensure request exists
            lastError = "No payment request" // Notify
            return // Exit
        } // End guard
        isLoading = true // Start loading
        do { // Begin try block
            try await api.lock(sid: request.sid, token: token) // Lock session
            resolveResult = request // Move to resolved (session is now locked)
            sessionLocked = true // Mark as locked
            showPaymentRequestSheet = false // Hide request sheet
            showPaySheet = true // Show confirmation/pay sheet
            lastError = nil // Clear errors
        } catch { // Handle errors
            if let apiError = error as? APIError { // Check if it's an API error
                lastError = apiError.error // Use the server error message
            } else { // Fallback to localized description
                lastError = error.localizedDescription // Use system error message
            } // End if
        } // End catch
        isLoading = false // Stop loading
    } // End acceptPaymentRequest
    
    func sendPayment() async { // Executes payment (session already locked)
        guard let token = authToken else { // Ensure logged in
            lastError = "Login first" // Notify user
            return // Exit
        } // End guard
        guard let resolved = resolveResult else { // Ensure session resolved and locked
            lastError = "No locked session" // Notify
            return // Exit
        } // End guard
        guard sessionLocked else { // Ensure session is locked
            lastError = "Session not locked" // Notify
            return // Exit
        } // End guard
        isLoading = true // Start loading
        do { // Begin try block
            _ = try await api.sendPayment(sid: resolved.sid, token: token, idempotencyKey: UUID().uuidString) // Send funds (session already locked)
            // Refresh wallet in background (don't wait if it fails)
            Task { await refreshWallet() } // Refresh wallet asynchronously
            // Clear all state immediately
            resolveResult = nil // Clear resolved state
            pendingPaymentRequest = nil // Clear pending request
            sessionLocked = false // Clear lock flag
            showPaySheet = false // Hide pay sheet
            showAcceptedOfferSheet = false // Hide accepted offer sheet
            acceptedOfferSID = nil // Clear accepted offer ID
            isLoading = false // Stop loading immediately after payment succeeds
        } catch { // Handle errors
            isLoading = false // Stop loading on error
            if let apiError = error as? APIError { // Check if it's an API error
                lastError = apiError.error // Use the server error message
            } else { // Fallback to localized description
                lastError = error.localizedDescription // Use system error message
            } // End if
        } // End catch
    } // End sendPayment
    
    func loadUsers() async { // Loads list of available users
        guard let token = authToken else { // Ensure token exists
            return // Exit if not logged in
        } // End guard
        isLoading = true // Start loading
        do { // Begin try block
            let response = try await api.listUsers(token: token) // Fetch users
            availableUsers = response.users // Update users list
            lastError = nil // Clear errors
        } catch { // Handle errors
            lastError = error.localizedDescription // Save error text
        } // End catch
        isLoading = false // Stop loading
    } // End loadUsers
    
    func loadPendingOffers() async { // Loads pending payment offers
        guard let token = authToken else { // Ensure token exists
            return // Exit if not logged in
        } // End guard
        isLoading = true // Start loading
        do { // Begin try block
            let response = try await api.getPendingOffers(token: token) // Fetch offers
            pendingOffers = response.offers // Update offers list
            lastError = nil // Clear errors
        } catch { // Handle errors
            lastError = error.localizedDescription // Save error text
        } // End catch
        isLoading = false // Stop loading
    } // End loadPendingOffers
    
    func createPaymentOffer() async { // Creates payment offer (push payment)
        guard let token = authToken else { // Ensure token present
            lastError = "Login first" // Notify missing auth
            return // Exit early
        } // End guard
        guard let payeeID = selectedUserID else { // Ensure user selected
            lastError = "Select a user" // Validation error
            return // Exit
        } // End guard
        guard let cents = centsFromDecimal(sendAmountInput) else { // Parse amount string to cents
            lastError = "Enter amount in dollars" // Validation error
            return // Exit
        } // End guard
        isLoading = true // Start loading
        do { // Begin try block
            let response = try await api.createPaymentOffer(payeeID: payeeID, amount: cents, token: token) // Create offer
            myCreatedOffers[response.sid] = response.eid // Track this offer
            lastError = nil // Clear errors
            sendAmountInput = "" // Clear amount
            selectedUserID = nil // Clear selection
            showSendMoneySheet = false // Hide sheet
            await loadPendingOffers() // Refresh offers (in case receiver checks)
            startOfferStatusPolling() // Start polling for offer acceptance
        } catch { // Handle errors
            if let apiError = error as? APIError { // Check if it's an API error
                lastError = apiError.error // Use the server error message
            } else { // Fallback to localized description
                lastError = error.localizedDescription // Use system error message
            } // End if
        } // End catch
        isLoading = false // Stop loading
    } // End createPaymentOffer
    
    private var offerStatusPollingTask: Task<Void, Never>? // Polling task for offer status
    
    func startOfferStatusPolling() { // Polls for accepted offers (sender side)
        offerStatusPollingTask?.cancel() // Cancel existing task
        guard authToken != nil else { return } // Exit if not logged in
        offerStatusPollingTask = Task { // Create task
            while !Task.isCancelled { // Continue until cancelled
                do { // Begin try block
                    try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                    await checkAcceptedOffers() // Check if any offers were accepted
                } catch { // Handle cancellation
                    break // Exit loop
                } // End catch
            } // End while
        } // End task
    } // End startOfferStatusPolling
    
    private func checkAcceptedOffers() async { // Checks if any of my offers were accepted
        guard let token = authToken else { return } // Exit if not logged in
        for (sid, eid) in myCreatedOffers { // Check each offer I created
            do { // Begin try block
                let resolved = try await api.resolve(eid: eid) // Try to resolve
                // Only show popup if session status is LOCKED (receiver has accepted)
                // For push payments, status changes: PENDING_ACCEPTANCE -> LOCKED (when accepted)
                if let status = resolved.status, status == "LOCKED" { // Session is locked (accepted)
                    if acceptedOfferSID != sid { // Haven't shown this yet
                        acceptedOfferSID = sid // Mark as accepted
                        resolveResult = resolved // Set resolved result
                        sessionLocked = true // Mark as locked
                        showAcceptedOfferSheet = true // Show pay sheet for sender
                        myCreatedOffers.removeValue(forKey: sid) // Remove from tracking
                    } // End if
                } // End if
            } catch { // Resolve failed (offer not accepted yet or doesn't exist)
                // Continue checking other offers
            } // End catch
        } // End for
    } // End checkAcceptedOffers
    
    func acceptPaymentOffer(sid: String) async { // Accepts a payment offer (receiver accepts, sender pays)
        guard let token = authToken else { // Ensure logged in
            lastError = "Login first" // Notify user
            return // Exit
        } // End guard
        isLoading = true // Start loading
        do { // Begin try block
            _ = try await api.acceptOffer(sid: sid, token: token) // Accept offer (session becomes LOCKED)
            // Keep popup open but mark as accepted - start polling for payment completion
            acceptedOfferSIDForReceiver = sid // Track accepted offer
            await loadPendingOffers() // Refresh offers list
            lastError = nil // Clear errors
            startPaymentCompletionPolling(sid: sid) // Start polling for payment completion
            isLoading = false // Stop loading (popup stays open showing loading state)
        } catch { // Handle errors
            isLoading = false // Stop loading on error
            if let apiError = error as? APIError { // Check if it's an API error
                lastError = apiError.error // Use the server error message
            } else { // Fallback to localized description
                lastError = error.localizedDescription // Use system error message
            } // End if
        } // End catch
    } // End acceptPaymentOffer
    
    func startPaymentCompletionPolling(sid: String) { // Polls for payment completion (receiver side)
        paymentCompletionPollingTask?.cancel() // Cancel existing task
        guard authToken != nil else { return } // Exit if not logged in
        paymentCompletionPollingTask = Task { // Create task
            while !Task.isCancelled { // Continue until cancelled
                do { // Begin try block
                    try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                    await checkPaymentCompletion(sid: sid) // Check if payment completed
                } catch is CancellationError { // Handle cancellation silently
                    break // Exit loop silently
                } catch { // Handle other errors silently
                    // Continue polling on other errors
                } // End catch
            } // End while
        } // End task
    } // End startPaymentCompletionPolling
    
    private func checkPaymentCompletion(sid: String) async { // Checks if payment was completed
        guard let token = authToken else { return } // Exit if not logged in
        do { // Begin try block
            // Check wallet for new transactions - if we see a RECEIVE_P2P transaction with this session ID, payment completed
            let wallet = try await api.fetchWallet(token: token) // Fetch wallet
            let paymentCompleted = wallet.recent.contains { entry in
                entry.type == "RECEIVE_P2P" && entry.ref_id == sid // Check if payment received
            } // End contains
            if paymentCompleted { // Payment completed!
                // Cancel polling task first (before state changes)
                paymentCompletionPollingTask?.cancel() // Stop polling
                paymentCompletionPollingTask = nil // Clear task reference
                // Update state
                completedOfferSID = sid // Mark as completed
                acceptedOfferSIDForReceiver = nil // Clear accepted tracking
                // Refresh wallet in background silently (don't show errors)
                Task { @MainActor in
                    guard authToken != nil else { return } // Exit if not logged in
                    do {
                        await refreshWallet() // Refresh wallet using existing method (handles errors silently)
                    } catch {
                        // Silently ignore wallet refresh errors - payment already completed
                        // Don't set lastError here - payment succeeded, wallet refresh is just a bonus
                    } // End catch
                } // End task
            } // End if
        } catch is CancellationError { // Handle cancellation silently
            // Task was cancelled - this is expected when payment completes
            return // Exit silently
        } catch { // Handle other errors silently
            // Continue polling on other errors
        } // End catch
    } // End checkPaymentCompletion
    
    private func centsFromDecimal(_ text: String) -> Int? { // Parses decimal string to cents
        let formatter = NumberFormatter() // Number formatter
        formatter.locale = .current // Use current locale
        formatter.numberStyle = .decimal // Support decimal inputs
        if let number = formatter.number(from: text) { // Attempt parse
            let doubleValue = number.doubleValue // Extract double
            return Int(doubleValue * 100) // Convert to cents
        } else if let direct = Double(text) { // Try manual Double parse
            return Int(direct * 100) // Convert to cents
        } else { // Parsing failed
            return nil // Return nil
        } // End branches
    } // End centsFromDecimal
} // End AppState

