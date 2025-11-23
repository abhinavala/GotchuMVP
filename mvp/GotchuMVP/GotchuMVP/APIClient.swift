//
//  APIClient.swift
//  GotchuMVP
//

import Foundation // Provides networking primitives

struct APIError: Error, Decodable, LocalizedError { // Represents API error payload
    let error: String // Error message returned by server
    
    var errorDescription: String? { // Provide localized error description
        return error // Return the server error message
    } // End errorDescription
} // End of APIError

struct AuthResponse: Decodable { // Response for dev login
    let token: String // JWT token string
    let user_id: String // Logged in user ID
} // End of AuthResponse

struct WalletEntry: Decodable, Identifiable { // Ledger entry model
    var id: String { ref_id } // Identifies entry via reference ID
    let type: String // Ledger type string
    let direction: String // Debit or credit direction
    let amount_cents: Int // Amount in cents
    let ref_type: String // Reference type string
    let ref_id: String // Reference identifier
    let created_at: String // Timestamp string
    
    enum CodingKeys: String, CodingKey { // Custom coding keys
        case type, direction, amount_cents, ref_type, ref_id, created_at // Map keys
    } // End CodingKeys
    
    init(from decoder: Decoder) throws { // Custom decoder
        let container = try decoder.container(keyedBy: CodingKeys.self) // Get container
        type = try container.decode(String.self, forKey: .type) // Decode type
        direction = try container.decode(String.self, forKey: .direction) // Decode direction
        ref_type = try container.decode(String.self, forKey: .ref_type) // Decode ref type
        ref_id = try container.decode(String.self, forKey: .ref_id) // Decode ref ID
        created_at = try container.decode(String.self, forKey: .created_at) // Decode timestamp
        // Handle both string and int for amount_cents
        if let intValue = try? container.decode(Int.self, forKey: .amount_cents) { // Try int first
            amount_cents = intValue // Use int value
        } else if let stringValue = try? container.decode(String.self, forKey: .amount_cents) { // Try string
            amount_cents = Int(stringValue) ?? 0 // Convert string to int
        } else { // Neither worked
            amount_cents = 0 // Default to zero
        } // End branches
    } // End init
} // End of WalletEntry

struct WalletResponse: Decodable { // Wallet endpoint payload
    let wallet_id: String // Wallet identifier
    let available_cents: Int // Balance in cents
    let recent: [WalletEntry] // Recent ledger entries
    
    enum CodingKeys: String, CodingKey { // Custom coding keys
        case wallet_id, available_cents, recent // Map keys
    } // End CodingKeys
    
    init(from decoder: Decoder) throws { // Custom decoder
        let container = try decoder.container(keyedBy: CodingKeys.self) // Get container
        wallet_id = try container.decode(String.self, forKey: .wallet_id) // Decode wallet ID
        recent = try container.decode([WalletEntry].self, forKey: .recent) // Decode entries
        // Handle both string and int for available_cents
        if let intValue = try? container.decode(Int.self, forKey: .available_cents) { // Try int first
            available_cents = intValue // Use int value
        } else if let stringValue = try? container.decode(String.self, forKey: .available_cents) { // Try string
            available_cents = Int(stringValue) ?? 0 // Convert string to int
        } else { // Neither worked
            available_cents = 0 // Default to zero
        } // End branches
    } // End init
} // End of WalletResponse

struct SessionResponse: Decodable, Identifiable, Equatable { // Session creation payload
    var id: String { sid } // Use sid as SwiftUI ID
    let sid: String // Session identifier
    let eid: String // Advertising EID
    let exp_at: String // Expiration timestamp
} // End of SessionResponse

struct ResolveResponse: Decodable { // Resolve endpoint payload
    let sid: String // Session identifier
    let amount_cents: Int // Amount in cents
    let payee_display: PayeeDisplay // Payee info
    
    enum CodingKeys: String, CodingKey { // Custom coding keys
        case sid, amount_cents, payee_display // Map keys
    } // End CodingKeys
    
    init(from decoder: Decoder) throws { // Custom decoder
        let container = try decoder.container(keyedBy: CodingKeys.self) // Get container
        sid = try container.decode(String.self, forKey: .sid) // Decode session ID
        payee_display = try container.decode(PayeeDisplay.self, forKey: .payee_display) // Decode payee
        // Handle both string and int for amount_cents
        if let intValue = try? container.decode(Int.self, forKey: .amount_cents) { // Try int first
            amount_cents = intValue // Use int value
        } else if let stringValue = try? container.decode(String.self, forKey: .amount_cents) { // Try string
            amount_cents = Int(stringValue) ?? 0 // Convert string to int
        } else { // Neither worked
            amount_cents = 0 // Default to zero
        } // End branches
    } // End init
} // End of ResolveResponse

struct PayeeDisplay: Decodable { // Payee info container
    let name: String // Display name
} // End of PayeeDisplay

struct SendResponse: Decodable { // Wallet send response
    let ok: Bool // Indicates success
    let new_balance_cents: Int // Updated balance
    
    enum CodingKeys: String, CodingKey { // Custom coding keys
        case ok, new_balance_cents // Map keys
    } // End CodingKeys
    
    init(from decoder: Decoder) throws { // Custom decoder
        let container = try decoder.container(keyedBy: CodingKeys.self) // Get container
        ok = try container.decode(Bool.self, forKey: .ok) // Decode ok flag
        // Handle both string and int for new_balance_cents
        if let intValue = try? container.decode(Int.self, forKey: .new_balance_cents) { // Try int first
            new_balance_cents = intValue // Use int value
        } else if let stringValue = try? container.decode(String.self, forKey: .new_balance_cents) { // Try string
            new_balance_cents = Int(stringValue) ?? 0 // Convert string to int
        } else { // Neither worked
            new_balance_cents = 0 // Default to zero
        } // End branches
    } // End init
} // End of SendResponse

@MainActor final class APIClient: ObservableObject { // Handles HTTP calls on main actor
    static let shared = APIClient() // Shared singleton for convenience
    private let session: URLSession // URLSession reference
    @Published var baseURL = URL(string: "http://Abhinavs-MacBook-Pro.local:3001")! // Default base URL (uses Bonjour hostname)
    
    private init() { // Private initializer for singleton
        let config = URLSessionConfiguration.default // Get default config
        config.timeoutIntervalForRequest = 10.0 // Set 10 second timeout
        config.timeoutIntervalForResource = 30.0 // Set 30 second resource timeout
        self.session = URLSession(configuration: config) // Create session with timeout
    } // End init
    
    func devLogin(email: String) async throws -> AuthResponse { // Performs dev login call
        let endpoint = baseURL.appendingPathComponent("auth/dev-login") // Construct endpoint URL
        var request = URLRequest(url: endpoint) // Create request object
        request.httpMethod = "POST" // Set HTTP method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type") // Indicate JSON body
        let body = ["email": email] // Body dictionary
        request.httpBody = try JSONEncoder().encode(body) // Serialize body
        return try await send(request: request) // Perform network call
    } // End devLogin
    
    func fetchWallet(token: String) async throws -> WalletResponse { // Fetches wallet info
        var request = authorizedRequest(path: "wallet/me", token: token) // Build authorized request
        return try await send(request: &request) // Execute call
    } // End fetchWallet
    
    func createSession(amount: Int, token: String) async throws -> SessionResponse { // Creates payment session
        var request = authorizedRequest(path: "sessions/create", token: token) // Build request
        request.httpMethod = "POST" // Use POST verb
        request.setValue("application/json", forHTTPHeaderField: "Content-Type") // JSON header
        let payload: [String: Any] = ["amount_cents": amount] // Payload dictionary
        request.httpBody = try JSONSerialization.data(withJSONObject: payload) // Serialize payload
        return try await send(request: &request) // Call server
    } // End createSession
    
    func resolve(eid: String) async throws -> ResolveResponse { // Resolves EID to session info
        var request = URLRequest(url: baseURL.appendingPathComponent("sessions/resolve")) // Build request
        request.httpMethod = "POST" // Use POST
        request.setValue("application/json", forHTTPHeaderField: "Content-Type") // JSON header
        request.httpBody = try JSONEncoder().encode(["eid": eid]) // Encode EID body
        return try await send(request: request) // Execute call
    } // End resolve
    
    func lock(sid: String, token: String) async throws { // Locks session for payment
        var request = authorizedRequest(path: "sessions/lock", token: token) // Build request
        request.httpMethod = "POST" // Use POST
        request.setValue("application/json", forHTTPHeaderField: "Content-Type") // JSON header
        request.httpBody = try JSONEncoder().encode(["sid": sid]) // Encode SID
        _ = try await send(request: request) as EmptyResponse // Ignore payload
    } // End lock
    
    func sendPayment(sid: String, token: String, idempotencyKey: String) async throws -> SendResponse { // Sends payment
        var request = authorizedRequest(path: "wallet/send", token: token) // Build request
        request.httpMethod = "POST" // Use POST
        request.setValue("application/json", forHTTPHeaderField: "Content-Type") // JSON header
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") // Include idempotency key
        request.httpBody = try JSONEncoder().encode(["sid": sid]) // Encode SID
        return try await send(request: request) // Execute call
    } // End sendPayment
    
    private func authorizedRequest(path: String, token: String) -> URLRequest { // Helper for auth requests
        var request = URLRequest(url: baseURL.appendingPathComponent(path)) // Build URL
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") // Attach bearer token
        return request // Return configured request
    } // End authorizedRequest
    
    private struct EmptyResponse: Decodable {} // Placeholder for endpoints with no body
    
    private func send<T: Decodable>(request: inout URLRequest) async throws -> T { // Generic send for inout request
        let urlString = request.url?.absoluteString ?? "unknown" // Get URL string
        print("🌐 API Request: \(request.httpMethod ?? "GET") \(urlString)") // Debug log
        print("🔗 Base URL: \(baseURL.absoluteString)") // Debug base URL
        do { // Begin error handling
            let (data, response) = try await session.data(for: request) // Perform network call
            if let httpResponse = response as? HTTPURLResponse { // Check if HTTP response
                print("✅ API Response: \(httpResponse.statusCode) from \(urlString)") // Debug log with status
            } else { // Not HTTP response
                print("✅ API Response: \(response)") // Debug log
            } // End if
            return try decodeResponse(data: data, response: response) // Decode typed payload
        } catch { // Catch network errors
            print("❌ API Error: \(error.localizedDescription)") // Debug log
            print("❌ Failed URL: \(urlString)") // Debug failed URL
            if let urlError = error as? URLError { // Check if URL error
                print("❌ URL Error Code: \(urlError.code.rawValue)") // Debug error code
                print("❌ URL Error Description: \(urlError.localizedDescription)") // Debug description
            } // End if
            throw error // Re-throw error
        } // End catch
    } // End send for inout
    
    private func send<T: Decodable>(request: URLRequest) async throws -> T { // Overload for immutable request
        var mutable = request // Copy to mutable var
        return try await send(request: &mutable) // Reuse main send logic
    } // End send overload
    
    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T { // Decodes HTTP responses
        guard let http = response as? HTTPURLResponse else { // Ensure HTTP response
            throw URLError(.badServerResponse) // Throw error if not
        } // End guard
        if (200..<300).contains(http.statusCode) { // Success range check
            do { // Begin error handling
                return try JSONDecoder().decode(T.self, from: data) // Decode success payload
            } catch { // Catch decoding errors
                let dataString = String(data: data, encoding: .utf8) ?? "Unable to convert data to string" // Get response as string
                print("❌ Decoding Error: \(error)") // Debug log
                print("❌ Response Data: \(dataString)") // Debug log
                throw error // Re-throw decoding error
            } // End catch
        } else { // Handle errors
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) { // Attempt to decode API error
                throw apiError // Propagate API error
            } else { // Fallback
                throw URLError(.badServerResponse) // Throw generic error
            } // End nested else
        } // End status check
    } // End decodeResponse
} // End APIClient

