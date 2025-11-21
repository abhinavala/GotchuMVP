# Gotchu MVP Architecture Overview

## 🏗️ System Architecture

```
┌─────────────────┐         ┌──────────────┐         ┌─────────────┐
│   iOS App A     │         │   iOS App B   │         │   Server    │
│  (Receiver)     │         │   (Payer)     │         │  (Node.js)  │
│                 │         │               │         │             │
│  Creates        │────────▶│  Scans BLE    │         │  Manages    │
│  Session        │  BLE    │  for EID      │         │  Sessions   │
│  Advertises EID │         │  Resolves     │────────▶│  & Wallets  │
│                 │         │  Locks & Pays │  HTTP   │             │
└─────────────────┘         └──────────────┘         └─────────────┘
                                      │
                                      ▼
                              ┌──────────────┐
                              │   Database   │
                              │  (Postgres)  │
                              │              │
                              │  - Users     │
                              │  - Wallets   │
                              │  - Sessions  │
                              │  - Ledger    │
                              └──────────────┘
```

---

## 📱 iOS App Components

### 1. **APIClient.swift** - Network Layer
**Purpose:** Handles all HTTP communication with the server

**Key Functions:**
- `devLogin(email:)` - Authenticates user, returns JWT token
- `fetchWallet(token:)` - Gets wallet balance and transaction history
- `createSession(amount:, token:)` - Creates a payment request session
- `resolve(eid:)` - Looks up session details from EID
- `lock(sid:, token:)` - Locks session to prevent double-payment
- `sendPayment(sid:, token:, idempotencyKey:)` - Executes the payment

**How it works:**
- Uses `URLSession` for HTTP requests
- Converts Swift objects to JSON for requests
- Converts JSON responses back to Swift objects
- Handles errors and timeouts
- **Important:** Handles PostgreSQL `bigint` → string conversion (database returns numbers as strings, we convert them to Int)

### 2. **AppState.swift** - Application State
**Purpose:** Central state management for the entire app

**Key Properties:**
- `email` - User's email input
- `authToken` - JWT token after login
- `wallet` - Current wallet balance and history
- `activeSession` - Currently created payment session (receiver side)
- `resolveResult` - Resolved session details (payer side)
- `baseURLString` - Server URL (editable)

**Key Functions:**
- `login()` - Calls API to authenticate, stores token, fetches wallet
- `createSession()` - Creates payment session, stores EID
- `resolveCurrent()` - Resolves EID to session details
- `sendPayment()` - Locks session, sends payment, refreshes wallet

**How it works:**
- Uses `@Published` properties so SwiftUI automatically updates when data changes
- All functions are `async` to handle network calls without blocking UI
- Manages the flow: login → create session → resolve → pay

### 3. **BLEManager.swift** - Bluetooth Communication
**Purpose:** Handles BLE advertising (receiver) and scanning (payer)

**Key Functions:**
- `startAdvertising(eid:)` - Broadcasts EID over BLE so nearby phones can find it
- `stopAdvertising()` - Stops broadcasting
- `startScanning()` - Scans for nearby EIDs
- `stopScanning()` - Stops scanning

**How it works:**
- **Receiver:** Uses `CBPeripheralManager` to advertise a BLE service
  - Service UUID: `0000FEED-0000-1000-8000-00805F9B34FB`
  - Service Data: The 10-character EID (hex string)
  - No PII (personal info) is broadcast - just the anonymous EID
  
- **Payer:** Uses `CBCentralManager` to scan for the service UUID
  - Filters by service UUID to find Gotchu sessions
  - Tracks RSSI (signal strength) to determine proximity
  - Lists discovered EIDs for user to select

**BLE Flow:**
1. Receiver creates session → gets EID → starts advertising
2. Payer starts scanning → detects EID → user selects it
3. EID is used to resolve session details via API

### 4. **ContentView.swift** - User Interface
**Purpose:** Main UI that displays all functionality

**Sections:**
- **Server Base URL** - Editable field to set API endpoint
- **Development Login** - Email input and sign-in button
- **Wallet** - Shows balance and recent transactions
- **Request Payment** - Create session, enter amount, advertise EID
- **Pay Nearby Session** - Enter EID manually or select from BLE scan
- **BLE Scanner** - Start/stop scanning, list discovered EIDs

**How it works:**
- Uses SwiftUI `@EnvironmentObject` to access shared state
- Automatically updates when `AppState` or `BLEManager` properties change
- Shows loading overlay during network operations
- Displays error alerts when operations fail

---

## 🖥️ Server Components

### 1. **Database Schema** (`docs/schema.sql`)

**Tables:**

#### `users`
- Stores user accounts (email, KYC status)
- Each user has a unique ID (UUID)

#### `wallet_accounts`
- One wallet per user
- `available_cents` - Current balance in cents (bigint)
- **Invariant:** Balance must equal sum of all ledger entries

#### `ledger_entries`
- Double-entry bookkeeping system
- Every transaction creates TWO entries:
  - **DEBIT** entry for sender (money out)
  - **CREDIT** entry for receiver (money in)
- Fields: `type`, `direction`, `amount_cents`, `ref_type`, `ref_id`
- **Why double-entry?** Ensures money is never created or destroyed, just moved

#### `payment_sessions`
- Represents a payment request
- `payee_id` - Who is requesting payment
- `amount_cents` - How much they want
- `status` - CREATED → ADVERTISING → LOCKED → PAID (or TIMEOUT/CANCEL)
- `exp_at` - Expiration timestamp (5 minutes)

#### `session_eids`
- Maps anonymous EIDs to payment sessions
- One session can have multiple EIDs (for privacy rotation, not used in MVP)
- EID is 10-character hex string (5 random bytes)

#### `idempotency_keys`
- Prevents duplicate payments
- If same request is sent twice with same key, second one is rejected
- Prevents accidental double-charging

### 2. **API Endpoints** (`src/index.ts`)

#### Authentication
**`POST /auth/dev-login`**
- Input: `{ email }`
- Output: `{ token, user_id }`
- Creates JWT token for development (no password needed)
- Token is used for all authenticated requests

#### Wallet
**`GET /wallet/me`** (requires auth)
- Returns: `{ wallet_id, available_cents, recent[] }`
- `recent` contains last 20 ledger entries

#### Sessions
**`POST /sessions/create`** (requires auth)
- Input: `{ amount_cents }`
- Output: `{ sid, eid, exp_at }`
- Creates new payment session
- Generates random EID
- Sets expiration to 5 minutes from now
- Status starts as "ADVERTISING"

**`POST /sessions/resolve`** (public)
- Input: `{ eid }`
- Output: `{ sid, amount_cents, payee_display }`
- Looks up session by EID
- Returns session details (but not who created it - privacy)
- Returns 410 if expired

**`POST /sessions/lock`** (requires auth)
- Input: `{ sid }`
- Output: `{ ok: true }`
- Locks session to prevent other payers from claiming it
- First lock wins - subsequent locks return 409 "busy"
- Status changes: ADVERTISING → LOCKED

#### Payments
**`POST /wallet/send`** (requires auth)
- Input: `{ sid }` + `Idempotency-Key` header
- Output: `{ ok: true, new_balance_cents }`
- **Critical flow:**
  1. Validates session exists and isn't expired
  2. Checks payer has sufficient funds
  3. Locks both wallets (prevents race conditions)
  4. Debits payer wallet
  5. Credits receiver wallet
  6. Creates two ledger entries (DEBIT + CREDIT)
  7. Marks session as PAID
  8. All in a single database transaction (atomic)

### 3. **Ledger Service** (`src/ledger.ts`)

**`postTransfer()`** - The core money movement function

**How it works:**
1. **Begin Transaction** - Starts database transaction
2. **Lock Sender Wallet** - `SELECT ... FOR UPDATE` prevents other operations
3. **Check Balance** - Ensures sender has enough funds
4. **Update Balances** - Debits sender, credits receiver
5. **Create Ledger Entries** - Inserts DEBIT and CREDIT entries
6. **Commit** - If all succeeds, commits transaction
7. **Rollback** - If anything fails, rolls back everything

**Why transactions?**
- Ensures atomicity: either everything succeeds or nothing changes
- Prevents race conditions: two payments can't happen simultaneously
- Maintains data integrity: balances always match ledger

### 4. **EID Generator** (`src/eid.ts`)

**`newEID()`** - Generates anonymous session identifier

**How it works:**
- Generates 5 random bytes
- Converts to 10-character hex string
- No PII (personal info) - completely anonymous
- Used in BLE advertisements so payer can find the session

---

## 🔄 Complete Payment Flow

### Scenario: Alice pays Bob $50

#### Step 1: Bob Creates Payment Request
1. Bob opens app, logs in as `bob@example.com`
2. Enters amount: `50.00`
3. Taps "Create Session"
4. **App calls:** `POST /sessions/create`
5. **Server:**
   - Creates `payment_sessions` row (status: ADVERTISING)
   - Generates EID: `a1b2c3d4e5`
   - Creates `session_eids` row linking EID to session
   - Returns: `{ sid: "uuid-123", eid: "a1b2c3d4e5", exp_at: "..." }`
6. **App:** Stores session, shows EID

#### Step 2: Bob Advertises EID
1. Bob taps "Advertise via BLE"
2. **BLEManager:** Starts `CBPeripheralManager`
3. Advertises BLE service with:
   - Service UUID: `0000FEED-0000-1000-8000-00805F9B34FB`
   - Service Data: `a1b2c3d4e5` (the EID)
4. Nearby phones can now detect this EID

#### Step 3: Alice Scans for Sessions
1. Alice opens app, logs in as `alice@example.com`
2. Taps "Start Scan" in BLE Scanner
3. **BLEManager:** Starts `CBCentralManager`
4. Scans for service UUID, finds Bob's advertisement
5. Extracts EID: `a1b2c3d4e5`
6. Shows in discovered EIDs list
7. Alice taps the EID (auto-fills resolve field)

#### Step 4: Alice Resolves Session
1. Alice taps "Resolve Session"
2. **App calls:** `POST /sessions/resolve { eid: "a1b2c3d4e5" }`
3. **Server:**
   - Looks up EID in `session_eids`
   - Finds session, checks not expired
   - Returns: `{ sid: "uuid-123", amount_cents: 5000, payee_display: { name: "bob" } }`
4. **App:** Shows "Pay $50.00 to bob?"

#### Step 5: Alice Confirms Payment
1. Alice taps "Lock & Pay"
2. **App calls:** `POST /sessions/lock { sid: "uuid-123" }`
3. **Server:**
   - Checks session status (must be CREATED or ADVERTISING)
   - Updates status to LOCKED
   - Returns: `{ ok: true }`
4. **App calls:** `POST /wallet/send { sid: "uuid-123" }` with Idempotency-Key
5. **Server:**
   - Checks idempotency (prevents duplicate)
   - Validates session not expired
   - Calls `postTransfer()`:
     - Locks Alice's wallet
     - Checks balance (must have ≥ $50)
     - Debits Alice: $100 → $50
     - Credits Bob: $0 → $50
     - Creates ledger entries:
       - Alice: DEBIT $50 (SEND_P2P)
       - Bob: CREDIT $50 (RECEIVE_P2P)
     - Marks session as PAID
   - Returns: `{ ok: true, new_balance_cents: 5000 }`
6. **App:** Refreshes wallet, shows updated balance

#### Step 6: Verification
- Alice's wallet: $50.00 (was $100)
- Bob's wallet: $50.00 (was $0)
- Ledger shows 2 entries (one DEBIT, one CREDIT)
- Session status: PAID

---

## 🔐 Security & Safety Features

### 1. **Session Locking**
- First payer to lock wins
- Prevents double-payment
- Status: ADVERTISING → LOCKED → PAID

### 2. **Idempotency**
- Each payment request includes unique `Idempotency-Key`
- Server stores keys for 24 hours
- Duplicate requests with same key are rejected
- Prevents accidental double-charging from network retries

### 3. **Balance Validation**
- Checks balance before transfer
- Throws "insufficient funds" if not enough
- Uses database locks (`FOR UPDATE`) to prevent race conditions

### 4. **Transaction Atomicity**
- All wallet operations in single database transaction
- Either everything succeeds or nothing changes
- Prevents partial payments or corrupted balances

### 5. **Session Expiration**
- Sessions expire after 5 minutes
- Prevents stale payment requests
- Expired sessions can't be locked or paid

### 6. **Privacy**
- EID is anonymous (no PII in BLE advertisement)
- Only amount and payee name shown (not email)
- No card data stored (only wallet balances)

---

## 🎯 Key Concepts

### Double-Entry Ledger
Every transaction creates TWO entries:
- **DEBIT** for sender (money out)
- **CREDIT** for receiver (money in)

**Why?** Ensures money is never created or destroyed. Total of all credits = total of all debits. Wallet balance = sum of all ledger entries for that wallet.

### EID (Encrypted Identifier)
- 10-character hex string
- Randomly generated for each session
- Used in BLE advertisements
- Maps to payment session via database
- No PII - completely anonymous

### Session Lifecycle
```
CREATED → ADVERTISING → LOCKED → PAID
   ↓         ↓            ↓
TIMEOUT   TIMEOUT     (success)
CANCEL    CANCEL
```

### BLE Advertisement
- **Service UUID:** Identifies Gotchu app
- **Service Data:** The EID (10 chars)
- **No PII:** Amount, payee name, etc. NOT in advertisement
- **Privacy:** Only EID is broadcast, details fetched via API

---

## 🚀 Next Steps (Future Enhancements)

1. **RSSI Gating** - Only show sessions when phones are very close (tap-to-target)
2. **Auto-Resolve** - Automatically resolve EID when detected (no manual tap)
3. **UI Polish** - Replace dev panel with production screens
4. **Android App** - Same BLE logic, different platform APIs
5. **Group Splits** - Multiple payers for one session
6. **EID Rotation** - Change EID periodically for privacy
7. **Push Notifications** - Alert when payment received (requires paid Apple Developer account)

---

## 📝 Summary

**The Flow:**
1. Receiver creates session → gets EID
2. Receiver advertises EID via BLE
3. Payer scans BLE → finds EID
4. Payer resolves EID → gets session details
5. Payer locks session → prevents double-payment
6. Payer sends payment → atomic wallet transfer
7. Both wallets update → ledger entries created

**Key Technologies:**
- **BLE** - Device discovery (advertising/scanning)
- **HTTP/REST** - API communication
- **PostgreSQL** - Data storage with transactions
- **JWT** - Authentication tokens
- **Double-Entry Ledger** - Financial integrity

**Core Principle:** Money moves atomically through database transactions, with BLE providing the "tap-to-target" discovery mechanism.

