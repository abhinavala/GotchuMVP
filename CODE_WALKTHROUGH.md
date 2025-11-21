# Gotchu MVP Code Walkthrough

## 📁 File-by-File Explanation

---

## iOS App Files

### `APIClient.swift` - Network Communication

**Purpose:** Handles all HTTP requests to the server

**Key Structures:**

```swift
struct AuthResponse {
    let token: String      // JWT token for authentication
    let user_id: String    // User's unique ID
}
```

**Why it exists:** Separates network logic from UI logic. Makes it easy to change API endpoints or add features.

**Key Functions Explained:**

1. **`devLogin(email:)`**
   - Builds POST request to `/auth/dev-login`
   - Sends email in JSON body
   - Returns token and user_id
   - Token is stored and used for all future requests

2. **`fetchWallet(token:)`**
   - GET request to `/wallet/me`
   - Includes `Authorization: Bearer <token>` header
   - Returns wallet balance and transaction history
   - **Custom decoder** handles PostgreSQL bigint → string conversion

3. **`createSession(amount:, token:)`**
   - POST to `/sessions/create`
   - Sends `amount_cents` (dollars converted to cents)
   - Returns session ID (sid) and EID (for BLE advertising)

4. **`resolve(eid:)`**
   - POST to `/sessions/resolve`
   - Sends EID (10-char hex string)
   - Returns session details (amount, payee name)
   - **No auth needed** - EID is the authorization

5. **`lock(sid:, token:)`**
   - POST to `/sessions/lock`
   - Locks session so only this payer can complete payment
   - Prevents race conditions (two people paying at once)

6. **`sendPayment(sid:, token:, idempotencyKey:)`**
   - POST to `/wallet/send`
   - Includes `Idempotency-Key` header (prevents duplicate payments)
   - Executes the actual money transfer
   - Returns new balance

**Error Handling:**
- All functions throw errors that can be caught
- `APIError` struct decodes server error messages
- Network errors (timeout, no connection) are also handled

---

### `AppState.swift` - Application State

**Purpose:** Central state container for the entire app

**Key Properties:**

```swift
@Published var email: String = ""              // User input
@Published var authToken: String?              // JWT after login
@Published var wallet: WalletResponse?         // Balance & history
@Published var activeSession: SessionResponse? // Created session
@Published var resolveResult: ResolveResponse? // Resolved session
```

**Why `@Published`?** SwiftUI automatically updates UI when these change.

**Key Functions Explained:**

1. **`login()`**
   ```swift
   func login() async {
       isLoading = true                    // Show spinner
       let response = try await api.devLogin(email: email)
       authToken = response.token          // Store token
       await refreshWallet()               // Fetch balance
       isLoading = false                   // Hide spinner
   }
   ```
   - Calls API to authenticate
   - Stores token for future requests
   - Automatically fetches wallet after login

2. **`createSession()`**
   ```swift
   func createSession() async {
       guard let cents = centsFromDecimal(amountInput) else { return }
       activeSession = try await api.createSession(amount: cents, token: token)
   }
   ```
   - Converts dollar amount to cents (e.g., "50.00" → 5000)
   - Creates session on server
   - Stores session (includes EID for BLE advertising)

3. **`resolveCurrent()`**
   ```swift
   func resolveCurrent() async {
       resolveResult = try await api.resolve(eid: resolveInput)
   }
   ```
   - Takes EID from input field (or BLE scan)
   - Looks up session details
   - Stores result (shows amount and payee name)

4. **`sendPayment()`**
   ```swift
   func sendPayment() async {
       try await api.lock(sid: resolved.sid, token: token)  // Lock first
       _ = try await api.sendPayment(...)                    // Then pay
       await refreshWallet()                                  // Update balance
   }
   ```
   - **Two-step process:** Lock then pay
   - Prevents other payers from claiming session
   - Refreshes wallet to show new balance

**State Flow:**
```
Login → Create Session → Advertise EID (BLE)
                              ↓
                        Payer Scans BLE
                              ↓
                        Resolve EID → Lock → Pay
```

---

### `BLEManager.swift` - Bluetooth Communication

**Purpose:** Handles BLE advertising and scanning

**Key Properties:**

```swift
@Published var isAdvertising = false      // Advertising status
@Published var discoveredEIDs: [String]  // List of found EIDs
@Published var statusText: String        // Status message
```

**How Advertising Works:**

1. **`startAdvertising(eid:)`**
   ```swift
   let serviceUUID = CBUUID(string: "0000FEED-0000-1000-8000-00805F9B34FB")
   let serviceData = eid.data(using: .utf8)
   // Advertise service with this data
   ```
   - Creates BLE service with Gotchu UUID
   - Encodes EID as service data
   - Starts `CBPeripheralManager` to broadcast
   - **No PII** - only EID is broadcast

2. **`startScanning()`**
   ```swift
   centralManager.scanForPeripherals(
       withServices: [serviceUUID],  // Only scan for Gotchu service
       options: nil
   )
   ```
   - Starts `CBCentralManager` to scan
   - Filters by service UUID (only finds Gotchu sessions)
   - When found, extracts EID from service data
   - Adds to `discoveredEIDs` list

**BLE Constants:**
- **Service UUID:** `0000FEED-0000-1000-8000-00805F9B34FB`
  - This is the "Gotchu" identifier
  - Both apps use same UUID to find each other
- **Service Data:** The EID (10-character hex)
  - This is what identifies the specific payment session

**Privacy:**
- Only EID is broadcast (anonymous)
- Amount, payee name, etc. are NOT in BLE
- Details fetched via API after EID is resolved

---

### `ContentView.swift` - User Interface

**Purpose:** Main UI that displays all functionality

**Structure:**
- Uses SwiftUI `@EnvironmentObject` to access shared state
- Automatically updates when state changes
- Shows loading overlay during network operations
- Displays error alerts

**Key Sections:**

1. **Server Base URL**
   - Text field to set API endpoint
   - Updates `AppState.baseURLString`
   - Used for all API calls

2. **Development Login**
   - Email input field
   - "Sign In" button calls `state.login()`
   - Shows token snippet when logged in

3. **Wallet**
   - Shows balance: `$\(wallet.available_cents / 100)`
   - Lists recent transactions
   - "Refresh" button calls `state.refreshWallet()`

4. **Request Payment**
   - Amount input (dollars)
   - "Create Session" button
   - Shows SID, EID, expiration when created
   - "Advertise via BLE" button

5. **Pay Nearby Session**
   - EID input field (manual or from BLE)
   - "Resolve Session" button
   - Shows amount and payee when resolved
   - "Lock & Pay" button

6. **BLE Scanner**
   - "Start Scan" / "Stop Scan" buttons
   - Lists discovered EIDs
   - Tapping EID fills resolve field

---

## Server Files

### `src/index.ts` - Main Server File

**Purpose:** Express.js server with all API endpoints

**Key Middleware:**
```typescript
app.use(cors())           // Allow cross-origin requests
app.use(express.json())   // Parse JSON request bodies
app.use(morgan("dev"))    // Log HTTP requests
```

**Endpoint Breakdown:**

1. **`POST /auth/dev-login`**
   ```typescript
   const r = await query("SELECT id FROM users WHERE email = $1", [email])
   res.json({ token: signDev(r.rows[0].id), user_id: r.rows[0].id })
   ```
   - Looks up user by email
   - Creates JWT token
   - Returns token and user_id

2. **`GET /wallet/me`** (requires auth)
   ```typescript
   const w = await query("SELECT id, available_cents FROM wallet_accounts WHERE user_id = $1", [userId])
   const h = await query("SELECT ... FROM ledger_entries WHERE wallet_id = $1", [wallet.id])
   res.json({ wallet_id, available_cents: Number(w.available_cents), recent: h.rows })
   ```
   - Gets wallet balance
   - Gets recent ledger entries
   - Converts bigint to number for JSON

3. **`POST /sessions/create`** (requires auth)
   ```typescript
   const exp = new Date(Date.now() + 300_000)  // 5 minutes
   const sid = (await query("INSERT INTO payment_sessions ...")).rows[0].id
   const eid = newEID()  // Random 10-char hex
   await query("INSERT INTO session_eids (session_id, eid) VALUES ($1, $2)", [sid, eid])
   res.json({ sid, eid, exp_at: exp.toISOString() })
   ```
   - Creates session with expiration
   - Generates random EID
   - Links EID to session

4. **`POST /sessions/resolve`**
   ```typescript
   const r = await query(`
     SELECT ps.id, ps.amount_cents, u.email
     FROM session_eids se
     JOIN payment_sessions ps ON se.session_id = ps.id
     JOIN users u ON ps.payee_id = u.id
     WHERE se.eid = $1
   `, [eid])
   res.json({ sid, amount_cents: Number(r.amount_cents), payee_display: { name: email.split("@")[0] } })
   ```
   - Looks up session by EID
   - Returns session details (but not full email - privacy)

5. **`POST /sessions/lock`** (requires auth)
   ```typescript
   if (!["CREATED", "ADVERTISING"].includes(r.rows[0].status)) {
     return res.status(409).json({ error: "busy" })
   }
   await query("UPDATE payment_sessions SET status = 'LOCKED' WHERE id = $1", [sid])
   ```
   - Only locks if status is CREATED or ADVERTISING
   - First lock wins - subsequent locks get 409

6. **`POST /wallet/send`** (requires auth)
   ```typescript
   await postTransfer({
     fromWalletId: pW.id,
     toWalletId: rW.id,
     amount_cents: Number(s.amount_cents),
     ref_type: "PAYMENT_SESSION",
     ref_id: s.id
   })
   await query("UPDATE payment_sessions SET status = 'PAID' WHERE id = $1", [sid])
   ```
   - Calls ledger service to move money
   - Marks session as PAID

---

### `src/ledger.ts` - Money Transfer Logic

**Purpose:** Handles atomic wallet-to-wallet transfers

**Key Function: `postTransfer()`**

```typescript
export async function postTransfer(o: {
  fromWalletId: string,
  toWalletId: string,
  amount_cents: number,
  ref_type: string,
  ref_id: string
}) {
  const client = await pool.connect()
  try {
    await client.query("BEGIN")  // Start transaction
    
    // Lock and check balance
    const fw = await client.query(
      "SELECT available_cents FROM wallet_accounts WHERE id = $1 FOR UPDATE",
      [o.fromWalletId]
    )
    const availableCents = Number(fw.rows[0].available_cents)
    if (availableCents < o.amount_cents) {
      throw new Error("insufficient funds")
    }
    
    // Update balances
    await client.query(
      "UPDATE wallet_accounts SET available_cents = available_cents - $1 WHERE id = $2",
      [o.amount_cents, o.fromWalletId]
    )
    await client.query(
      "UPDATE wallet_accounts SET available_cents = available_cents + $1 WHERE id = $2",
      [o.amount_cents, o.toWalletId]
    )
    
    // Create ledger entries (double-entry)
    await client.query(`
      INSERT INTO ledger_entries (wallet_id, type, direction, amount_cents, ref_type, ref_id)
      VALUES ($1, 'SEND_P2P', 'DEBIT', $3, $4, $5),
             ($2, 'RECEIVE_P2P', 'CREDIT', $3, $4, $5)
    `, [o.fromWalletId, o.toWalletId, o.amount_cents, o.ref_type, o.ref_id])
    
    await client.query("COMMIT")  // Success - commit transaction
  } catch (e) {
    await client.query("ROLLBACK")  // Error - rollback everything
    throw e
  } finally {
    client.release()
  }
}
```

**Why Transactions?**
- **Atomicity:** All operations succeed or all fail
- **Isolation:** `FOR UPDATE` lock prevents concurrent modifications
- **Consistency:** Balances always match ledger entries
- **Durability:** Committed changes are permanent

**Double-Entry Bookkeeping:**
- Every transfer creates TWO ledger entries
- DEBIT for sender (money out)
- CREDIT for receiver (money in)
- Ensures: Total credits = Total debits (money conservation)

---

### `src/eid.ts` - EID Generation

**Purpose:** Generates anonymous session identifiers

```typescript
export const newEID = (): string => {
  return randomBytes(5).toString("hex")  // 10 characters
}
```

**Why 5 bytes?**
- 5 bytes = 10 hex characters
- 2^40 possible values (1 trillion+)
- Collision probability is negligible
- Small enough for BLE service data

**Properties:**
- **Random:** Cryptographically secure random bytes
- **Anonymous:** No PII encoded
- **Short:** Fits in BLE advertisement
- **Unique:** Very low collision probability

---

### `src/auth.ts` - Authentication

**Purpose:** JWT token creation and validation

**Functions:**

1. **`signDev(uid)`**
   ```typescript
   return jwt.sign({ uid }, process.env.JWT_SECRET!, { expiresIn: "7d" })
   ```
   - Creates JWT token with user ID
   - Expires in 7 days
   - Signed with secret key

2. **`requireAuth(req, res, next)`**
   ```typescript
   const token = req.headers.authorization.replace(/^Bearer /, "")
   const payload = jwt.verify(token, process.env.JWT_SECRET!)
   req.userId = payload.uid
   next()
   ```
   - Extracts token from Authorization header
   - Verifies token signature
   - Extracts user ID
   - Adds to request object for use in endpoints

---

## 🔄 Data Flow Example

### Complete Payment: Alice pays Bob $50

1. **Bob creates session:**
   ```
   App → POST /sessions/create { amount_cents: 5000 }
   Server → Creates session, generates EID "a1b2c3d4e5"
   Server → Returns { sid: "uuid-123", eid: "a1b2c3d4e5" }
   App → Stores session, starts BLE advertising
   ```

2. **Alice scans:**
   ```
   App → Starts BLE scan
   BLE → Detects service UUID, extracts EID "a1b2c3d4e5"
   App → Shows EID in discovered list
   ```

3. **Alice resolves:**
   ```
   App → POST /sessions/resolve { eid: "a1b2c3d4e5" }
   Server → Looks up EID in database
   Server → Returns { sid: "uuid-123", amount_cents: 5000, payee_display: { name: "bob" } }
   App → Shows "Pay $50.00 to bob?"
   ```

4. **Alice pays:**
   ```
   App → POST /sessions/lock { sid: "uuid-123" }
   Server → Updates status to LOCKED
   
   App → POST /wallet/send { sid: "uuid-123" }
   Server → Calls postTransfer():
     - Locks Alice's wallet (FOR UPDATE)
     - Checks balance: $100 >= $50 ✓
     - Debits Alice: $100 → $50
     - Credits Bob: $0 → $50
     - Creates ledger: Alice DEBIT $50, Bob CREDIT $50
     - Commits transaction
   Server → Updates session status to PAID
   Server → Returns { ok: true, new_balance_cents: 5000 }
   
   App → Refreshes wallet, shows new balance
   ```

---

## 🎯 Key Design Decisions

### Why BLE instead of NFC?
- **Cross-platform:** Works on both iOS and Android
- **Range:** Can detect nearby devices (not just touching)
- **Privacy:** Only broadcasts anonymous EID
- **No special hardware:** Works on all modern phones

### Why EID instead of direct session ID?
- **Privacy:** EID is anonymous, session ID reveals user
- **Security:** EID can be rotated without exposing session
- **Flexibility:** One session can have multiple EIDs

### Why double-entry ledger?
- **Integrity:** Ensures money is never created or destroyed
- **Audit trail:** Complete history of all transactions
- **Reconciliation:** Can verify balances match ledger

### Why session locking?
- **Race condition prevention:** Two payers can't pay simultaneously
- **First-come-first-served:** First lock wins
- **Clear error messages:** "busy" if someone else locked it

### Why idempotency keys?
- **Network retry safety:** Prevents duplicate payments from retries
- **User error protection:** Accidental double-tap won't charge twice
- **24-hour window:** Keys stored temporarily, then cleared

---

This architecture ensures:
- ✅ Money moves atomically (transactions)
- ✅ No double-payments (locking + idempotency)
- ✅ Privacy (anonymous EIDs)
- ✅ Integrity (double-entry ledger)
- ✅ Safety (balance checks, expiration)

