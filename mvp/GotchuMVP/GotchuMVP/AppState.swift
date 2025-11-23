//
//  AppState.swift
//  GotchuMVP
//

import Foundation // Provides Combine + async features

@MainActor final class AppState: ObservableObject { // Central state container
    @Published var email: String = "" // Stores user email input
    @Published var authToken: String? // Holds JWT token
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
            lastError = nil // Clear errors
            await refreshWallet() // Fetch wallet after login
        } catch { // Handle errors
            lastError = error.localizedDescription // Save error text
        } // End catch
        isLoading = false // Stop loading indicator
    } // End login
    
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
            await refreshWallet() // Refresh wallet
            resolveResult = nil // Clear resolved state
            pendingPaymentRequest = nil // Clear pending request
            sessionLocked = false // Clear lock flag
            showPaySheet = false // Hide pay sheet
        } catch { // Handle errors
            if let apiError = error as? APIError { // Check if it's an API error
                lastError = apiError.error // Use the server error message
            } else { // Fallback to localized description
                lastError = error.localizedDescription // Use system error message
            } // End if
        } // End catch
        isLoading = false // Stop spinner
    } // End sendPayment
    
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

