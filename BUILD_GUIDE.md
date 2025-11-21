# Gotchu MVP Build Guide
## Step-by-Step Instructions for Free Apple Developer Account

This guide walks you through building the Gotchu MVP (Option A only) with a free Apple Developer account.

---

## ✅ Pre-Flight Checklist

Before starting, verify you have:

- [ ] **Node.js 20+** installed (`node -v`)
- [ ] **npm** installed (`npm -v`)
- [ ] **PostgreSQL 14+** installed (`psql --version`) OR **Neon account** (cloud Postgres)
- [ ] **Xcode 15+** installed and opened at least once
- [ ] **Git** installed (`git --version`)
- [ ] **Free Apple Developer account** (sign in at developer.apple.com)

---

## 📦 Phase 0: Project Structure Setup

### Step 0.1: Create Directory Structure

```bash
cd /Users/abhinavala/Desktop/gotchu
mkdir -p server/src server/docs
mkdir -p mobile/ios mobile/android
```

**Verify:** Run `tree -L 2` (or `find . -type d -maxdepth 2`) to see folders.

---

## 🖥️ Phase 1: API Server Bootstrap

### Step 1.1: Initialize Node.js Project

```bash
cd server
npm init -y
```

### Step 1.2: Install Dependencies

```bash
npm install express zod cors morgan pg dotenv jsonwebtoken uuid qrcode
npm install -D typescript ts-node-dev @types/node @types/express @types/jsonwebtoken @types/uuid @types/qrcode
```

### Step 1.3: Initialize TypeScript

```bash
npx tsc --init
```

**Edit `tsconfig.json`** to set:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

### Step 1.4: Create Basic Server

Create `server/src/index.ts`:

```typescript
import express from "express";
import morgan from "morgan";
import cors from "cors";
import dotenv from "dotenv";

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());
app.use(morgan("dev"));

app.get("/health", (_, res) => res.send("OK"));

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`API running on http://localhost:${PORT}`);
});
```

### Step 1.5: Update package.json Scripts

Add to `package.json`:
```json
{
  "scripts": {
    "dev": "ts-node-dev --respawn src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  }
}
```

### Step 1.6: Create Environment File

Create `server/.env`:
```
PORT=3001
DATABASE_URL=postgres://USER:PASS@localhost:5432/gotchu
JWT_SECRET=change_me_to_random_string_min_32_chars
APP_BASE_URL=http://localhost:3001
```

**⚠️ Replace `DATABASE_URL` with your actual Postgres connection string.**

**Verify:** Run `npm run dev` → visit `http://localhost:3001/health` → should return "OK"

---

## 🗄️ Phase 2: Database Setup

### Step 2.1: Create Database

**Option A: Local Postgres**
```bash
createdb gotchu
```

**Option B: Neon (Cloud)**
- Go to neon.tech
- Create project → copy connection string
- Update `DATABASE_URL` in `.env`

### Step 2.2: Create Schema

Create `server/docs/schema.sql`:

```sql
create extension if not exists pgcrypto;

create table users (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  kyc_status text default 'verified',
  stripe_account_id text
);

create table wallet_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  available_cents bigint not null default 0
);

create table ledger_entries (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references wallet_accounts(id),
  type text not null,
  direction text not null,
  amount_cents bigint not null,
  ref_type text not null,
  ref_id text not null,
  created_at timestamptz not null default now()
);

create table payment_sessions (
  id uuid primary key default gen_random_uuid(),
  payee_id uuid not null references users(id),
  amount_cents bigint not null,
  split_mode text not null default 'single',
  max_payers int not null default 1,
  status text not null default 'CREATED',
  exp_at timestamptz not null
);

create table session_eids (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references payment_sessions(id) on delete cascade,
  eid text not null,
  rotated_at timestamptz not null default now()
);

create table payment_groups (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references payment_sessions(id) on delete cascade,
  total_cents bigint not null,
  split_mode text not null default 'equal'
);

create table group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references payment_groups(id) on delete cascade,
  payer_id uuid not null references users(id),
  share_cents bigint not null,
  state text not null default 'JOINED'
);

create table idempotency_keys (
  key text primary key,
  user_id uuid not null references users(id),
  route text not null,
  ref text,
  created_at timestamptz not null default now()
);

create index idx_session_eids_eid on session_eids(eid);
create index idx_ledger_wallet_id on ledger_entries(wallet_id);
create index idx_idempotency_user_route on idempotency_keys(user_id, route);
```

### Step 2.3: Load Schema

**Local Postgres:**
```bash
psql gotchu < server/docs/schema.sql
```

**Neon:**
- Use their SQL editor or `psql` with your connection string:
```bash
psql "your-neon-connection-string" < server/docs/schema.sql
```

### Step 2.4: Seed Test Users

```bash
psql gotchu -c "
INSERT INTO users (email) VALUES 
  ('alice@example.com'), 
  ('bob@example.com');
  
INSERT INTO wallet_accounts (user_id)
SELECT id FROM users ORDER BY email;

UPDATE wallet_accounts SET available_cents = 10000 
WHERE user_id IN (SELECT id FROM users WHERE email = 'alice@example.com');
"
```

**Verify:** 
```bash
psql gotchu -c "SELECT u.email, w.available_cents FROM users u JOIN wallet_accounts w ON u.id = w.user_id;"
```
Should show 2 users with wallets.

### Step 2.5: Create DB Helper

Create `server/src/db.ts`:

```typescript
import { Pool } from "pg";

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

export const query = async (sql: string, params?: any[]) => {
  const result = await pool.query(sql, params);
  return result;
};
```

**Verify:** Import in `index.ts` and test:
```typescript
import { query } from "./db";
// In a test route:
app.get("/test-db", async (_, res) => {
  const result = await query("SELECT 1 as test");
  res.json(result.rows);
});
```
Visit `/test-db` → should return `[{"test": 1}]`

---

## 🔐 Phase 3: Dev Authentication

### Step 3.1: Create Auth Module

Create `server/src/auth.ts`:

```typescript
import jwt from "jsonwebtoken";
import { Request, Response, NextFunction } from "express";

export function signDev(uid: string): string {
  return jwt.sign({ uid }, process.env.JWT_SECRET!, { expiresIn: "7d" });
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const token = (req.headers.authorization || "").replace(/^Bearer /, "");
  if (!token) {
    return res.status(401).json({ error: "unauthorized" });
  }
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET!) as any;
    (req as any).userId = payload.uid;
    next();
  } catch {
    res.status(401).json({ error: "unauthorized" });
  }
}
```

### Step 3.2: Add Dev Login Endpoint

Add to `server/src/index.ts`:

```typescript
import { signDev, requireAuth } from "./auth";

app.post("/auth/dev-login", async (req, res) => {
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ error: "email required" });
  }
  const r = await query("SELECT id FROM users WHERE email = $1", [email]);
  if (!r.rows.length) {
    return res.status(404).json({ error: "not found" });
  }
  res.json({
    token: signDev(r.rows[0].id),
    user_id: r.rows[0].id,
  });
});
```

**Verify:**
```bash
curl -X POST http://localhost:3001/auth/dev-login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com"}'
```
Should return `{"token":"...", "user_id":"..."}`

---

## 💰 Phase 4: Wallet & Ledger

### Step 4.1: Create Ledger Service

Create `server/src/ledger.ts`:

```typescript
import { pool } from "./db";

export async function postTransfer(o: {
  fromWalletId: string;
  toWalletId: string;
  amount_cents: number;
  ref_type: string;
  ref_id: string;
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    // Lock and check sender balance
    const fw = await client.query(
      "SELECT available_cents FROM wallet_accounts WHERE id = $1 FOR UPDATE",
      [o.fromWalletId]
    );
    if (!fw.rows.length) {
      throw new Error("from wallet not found");
    }
    if (fw.rows[0].available_cents < o.amount_cents) {
      throw new Error("insufficient funds");
    }

    // Update balances
    await client.query(
      "UPDATE wallet_accounts SET available_cents = available_cents - $1 WHERE id = $2",
      [o.amount_cents, o.fromWalletId]
    );
    await client.query(
      "UPDATE wallet_accounts SET available_cents = available_cents + $1 WHERE id = $2",
      [o.amount_cents, o.toWalletId]
    );

    // Insert ledger entries
    await client.query(
      `INSERT INTO ledger_entries (wallet_id, type, direction, amount_cents, ref_type, ref_id)
       VALUES ($1, 'SEND_P2P', 'DEBIT', $3, $4, $5),
              ($2, 'RECEIVE_P2P', 'CREDIT', $3, $4, $5)`,
      [o.fromWalletId, o.toWalletId, o.amount_cents, o.ref_type, o.ref_id]
    );

    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
```

### Step 4.2: Add Wallet Endpoints

Add to `server/src/index.ts`:

```typescript
import { postTransfer } from "./ledger";

app.get("/wallet/me", requireAuth, async (req, res) => {
  const userId = (req as any).userId;
  const w = await query(
    "SELECT id, available_cents FROM wallet_accounts WHERE user_id = $1",
    [userId]
  );
  if (!w.rows.length) {
    return res.status(404).json({ error: "wallet not found" });
  }
  const wallet = w.rows[0];
  const h = await query(
    `SELECT type, direction, amount_cents, ref_type, ref_id, created_at
     FROM ledger_entries
     WHERE wallet_id = $1
     ORDER BY created_at DESC
     LIMIT 20`,
    [wallet.id]
  );
  res.json({
    wallet_id: wallet.id,
    available_cents: wallet.available_cents,
    recent: h.rows,
  });
});
```

**Verify:**
```bash
# Get token first
TOKEN=$(curl -s -X POST http://localhost:3001/auth/dev-login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com"}' | jq -r '.token')

# Check wallet
curl -H "Authorization: Bearer $TOKEN" http://localhost:3001/wallet/me
```
Should return balance and history.

---

## 🎯 Phase 5: Payment Sessions

### Step 5.1: Create EID Generator

Create `server/src/eid.ts`:

```typescript
import { randomBytes } from "crypto";

export const newEID = (): string => {
  return randomBytes(5).toString("hex"); // 10 chars
};
```

### Step 5.2: Add Session Endpoints

Add to `server/src/index.ts`:

```typescript
import { newEID } from "./eid";

app.post("/sessions/create", requireAuth, async (req, res) => {
  const { amount_cents, split_mode = "single", max_payers = 1 } = req.body;
  if (!Number.isInteger(amount_cents) || amount_cents <= 0) {
    return res.status(400).json({ error: "invalid amount" });
  }
  const exp = new Date(Date.now() + 60_000); // 60s TTL
  const userId = (req as any).userId;
  const ins = await query(
    `INSERT INTO payment_sessions (payee_id, amount_cents, split_mode, max_payers, exp_at, status)
     VALUES ($1, $2, $3, $4, $5, 'ADVERTISING')
     RETURNING id`,
    [userId, amount_cents, split_mode, max_payers, exp]
  );
  const sid = ins.rows[0].id;
  const eid = newEID();
  await query("INSERT INTO session_eids (session_id, eid) VALUES ($1, $2)", [
    sid,
    eid,
  ]);
  res.json({ sid, eid, exp_at: exp.toISOString() });
});

app.post("/sessions/resolve", async (req, res) => {
  const { eid } = req.body;
  if (!eid) {
    return res.status(400).json({ error: "eid required" });
  }
  const r = await query(
    `SELECT ps.id as sid, ps.amount_cents, ps.exp_at, u.email
     FROM session_eids se
     JOIN payment_sessions ps ON se.session_id = ps.id
     JOIN users u ON ps.payee_id = u.id
     WHERE se.eid = $1
     ORDER BY se.rotated_at DESC
     LIMIT 1`,
    [eid]
  );
  if (!r.rows.length) {
    return res.status(404).json({ error: "not found" });
  }
  if (new Date(r.rows[0].exp_at) < new Date()) {
    return res.status(410).json({ error: "expired" });
  }
  res.json({
    sid: r.rows[0].sid,
    amount_cents: r.rows[0].amount_cents,
    payee_display: { name: r.rows[0].email.split("@")[0] },
  });
});

app.post("/sessions/lock", requireAuth, async (req, res) => {
  const { sid } = req.body;
  if (!sid) {
    return res.status(400).json({ error: "sid required" });
  }
  const r = await query(
    "SELECT status, exp_at FROM payment_sessions WHERE id = $1",
    [sid]
  );
  if (!r.rows.length) {
    return res.status(404).json({ error: "not found" });
  }
  if (new Date(r.rows[0].exp_at) < new Date()) {
    return res.status(410).json({ error: "expired" });
  }
  if (!["CREATED", "ADVERTISING"].includes(r.rows[0].status)) {
    return res.status(409).json({ error: "busy" });
  }
  await query("UPDATE payment_sessions SET status = 'LOCKED' WHERE id = $1", [
    sid,
  ]);
  res.json({ ok: true });
});

app.post("/wallet/send", requireAuth, async (req, res) => {
  const { sid } = req.body;
  const idempotencyKey = req.headers["idempotency-key"] as string;

  if (!sid) {
    return res.status(400).json({ error: "sid required" });
  }

  const userId = (req as any).userId;

  // Check idempotency
  if (idempotencyKey) {
    const existing = await query(
      "SELECT * FROM idempotency_keys WHERE key = $1",
      [idempotencyKey]
    );
    if (existing.rows.length) {
      return res.status(409).json({ error: "duplicate request" });
    }
  }

  const sr = await query(
    "SELECT id, payee_id, amount_cents, status, exp_at FROM payment_sessions WHERE id = $1",
    [sid]
  );
  if (!sr.rows.length) {
    return res.status(404).json({ error: "session not found" });
  }
  const s = sr.rows[0];
  if (new Date(s.exp_at) < new Date()) {
    return res.status(410).json({ error: "expired" });
  }
  if (!["LOCKED", "CREATED", "ADVERTISING"].includes(s.status)) {
    return res.status(409).json({ error: "busy/paid" });
  }
  if (userId === s.payee_id) {
    return res.status(400).json({ error: "cannot pay self" });
  }

  const pW = (
    await query("SELECT id FROM wallet_accounts WHERE user_id = $1", [userId])
  ).rows[0];
  const rW = (
    await query("SELECT id FROM wallet_accounts WHERE user_id = $1", [
      s.payee_id,
    ])
  ).rows[0];

  try {
    await postTransfer({
      fromWalletId: pW.id,
      toWalletId: rW.id,
      amount_cents: s.amount_cents,
      ref_type: "PAYMENT_SESSION",
      ref_id: s.id,
    });
    await query("UPDATE payment_sessions SET status = 'PAID' WHERE id = $1", [
      sid,
    ]);

    if (idempotencyKey) {
      await query(
        "INSERT INTO idempotency_keys (key, user_id, route, ref) VALUES ($1, $2, $3, $4)",
        [idempotencyKey, userId, "/wallet/send", sid]
      );
    }

    const nb = (
      await query(
        "SELECT available_cents FROM wallet_accounts WHERE id = $1",
        [pW.id]
      )
    ).rows[0].available_cents;
    res.json({ ok: true, new_balance_cents: nb });
  } catch (e: any) {
    res.status(400).json({ error: e.message });
  }
});
```

**Verify:** Test the flow:
1. Create session → get `{sid, eid}`
2. Resolve EID → get session details
3. Lock session → get `{ok: true}`
4. Send payment → money moves

---

## 📱 Phase 6: QR Deep Link Fallback

### Step 6.1: Add QR Endpoint

Add to `server/src/index.ts`:

```typescript
import QRCode from "qrcode";

app.get("/deeplink/pay", async (req, res) => {
  const { sid } = req.query as any;
  if (!sid) {
    return res.status(400).json({ error: "sid required" });
  }
  const link = `gotchu://pay?sid=${sid}`;
  try {
    const img = await QRCode.toDataURL(link);
    res.setHeader("Content-Type", "text/html");
    res.send(`
      <h3>Open in Gotchu to pay</h3>
      <a href="${link}">${link}</a><br/>
      <img src="${img}" width="220" alt="QR Code"/>
    `);
  } catch (e) {
    res.status(500).json({ error: "failed to generate QR" });
  }
});
```

**Verify:** Visit `http://localhost:3001/deeplink/pay?sid=<some-sid>` → see QR code

---

## 📲 Phase 7: iOS App Setup

### Step 7.1: Configure Xcode Project

1. **Open** `mvp/GotchuMVP/GotchuMVP.xcodeproj` in Xcode

2. **Set Signing:**
   - Select project → Target "GotchuMVP"
   - Signing & Capabilities
   - Team: Select your Apple ID (free account)
   - Bundle Identifier: `com.yourname.gotchu` (change if needed)
   - ✅ "Automatically manage signing"

3. **Add Bluetooth Permission:**
   - Select Info.plist (or add to target's Info tab)
   - Add key: `NSBluetoothAlwaysUsageDescription`
   - Value: `"Used to discover nearby pay requests."`

4. **Add Background Mode (Optional, for foreground reliability):**
   - Signing & Capabilities → + Capability → Background Modes
   - ✅ "Uses Bluetooth LE accessories"

### Step 7.2: Register URL Scheme

1. In Xcode → Target → Info → URL Types
2. Click + → Add:
   - Identifier: `gotchu`
   - URL Schemes: `gotchu`

### Step 7.3: Add CoreBluetooth Framework

In Xcode → Target → Build Phases → Link Binary With Libraries:
- Add `CoreBluetooth.framework`

**Verify:** Project builds without errors (`Cmd+B`)

---

## 🎨 Phase 8: iOS App Implementation

### Step 8.1: Create BLE Constants

Create `mvp/GotchuMVP/GotchuMVP/BLEConstants.swift`:

```swift
import CoreBluetooth

struct BLEConstants {
    static let serviceUUID = CBUUID(string: "0000FEED-0000-1000-8000-00805F9B34FB")
    static let serviceDataKey = "0000FEED-0000-1000-8000-00805F9B34FB"
}
```

### Step 8.2: Create API Client

Create `mvp/GotchuMVP/GotchuMVP/APIClient.swift`:

```swift
import Foundation

class APIClient {
    static let shared = APIClient()
    let baseURL = "http://localhost:3001" // Change to your server IP for device testing
    
    var authToken: String?
    
    func devLogin(email: String) async throws -> (token: String, userId: String) {
        // Implementation here
    }
    
    func createSession(amountCents: Int) async throws -> SessionResponse {
        // Implementation here
    }
    
    func resolveEID(_ eid: String) async throws -> ResolveResponse {
        // Implementation here
    }
    
    func lockSession(sid: String) async throws {
        // Implementation here
    }
    
    func sendPayment(sid: String, idempotencyKey: String) async throws -> SendResponse {
        // Implementation here
    }
    
    func getWallet() async throws -> WalletResponse {
        // Implementation here
    }
}

struct SessionResponse: Codable {
    let sid: String
    let eid: String
    let exp_at: String
}

struct ResolveResponse: Codable {
    let sid: String
    let amount_cents: Int
    let payee_display: PayeeDisplay
}

struct PayeeDisplay: Codable {
    let name: String
}

struct SendResponse: Codable {
    let ok: Bool
    let new_balance_cents: Int
}

struct WalletResponse: Codable {
    let wallet_id: String
    let available_cents: Int
    let recent: [LedgerEntry]
}

struct LedgerEntry: Codable {
    let type: String
    let direction: String
    let amount_cents: Int
    let ref_type: String
    let ref_id: String
    let created_at: String
}
```

### Step 8.3: Create BLE Manager

Create `mvp/GotchuMVP/GotchuMVP/BLEManager.swift`:

```swift
import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()
    
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    
    @Published var isAdvertising = false
    @Published var discoveredEID: String?
    @Published var rssi: Int = -100
    
    // RSSI tracking
    private var rssiSamples: [String: [Int]] = [:]
    private let rssiThreshold = -60 // dBm
    private let requiredSamples = 4
    private let sampleWindow = 5
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func startAdvertising(eid: String) {
        // Implementation
    }
    
    func stopAdvertising() {
        // Implementation
    }
    
    func startScanning() {
        // Implementation
    }
    
    func stopScanning() {
        // Implementation
    }
}

extension BLEManager: CBCentralManagerDelegate {
    // Implementation
}

extension BLEManager: CBPeripheralManagerDelegate {
    // Implementation
}
```

### Step 8.4: Create UI Screens

You'll need:
- **RequestView**: Amount input → create session → advertise
- **PaySheet**: Shows when nearby session detected → confirm payment
- **WalletView**: Balance + history
- **HistoryView**: List of ledger entries

**Note:** Full SwiftUI implementation is extensive. Start with basic screens and wire up BLE + API calls.

---

## ✅ Verification Checklist

After completing each phase, verify:

- [ ] **Phase 1:** Server runs, `/health` returns OK
- [ ] **Phase 2:** Database has tables, test users exist
- [ ] **Phase 3:** `/auth/dev-login` returns token
- [ ] **Phase 4:** `/wallet/me` returns balance
- [ ] **Phase 5:** Can create session, resolve EID, lock, and send payment
- [ ] **Phase 6:** QR endpoint generates QR code
- [ ] **Phase 7:** iOS app builds and runs on device
- [ ] **Phase 8:** BLE advertising/scanning works, payments complete

---

## 🚨 Common Issues & Fixes

### Server won't start
- Check `DATABASE_URL` is correct
- Ensure Postgres is running: `pg_isready`

### BLE not working on iOS
- Check Info.plist has Bluetooth permission
- Test on physical device (BLE doesn't work in simulator)
- Verify app is in foreground

### Database connection errors
- Check `.env` file exists and has correct `DATABASE_URL`
- For Neon: ensure connection string includes `?sslmode=require`

### Xcode signing errors
- Free account: Use your Apple ID as team
- Bundle ID must be unique (add your name/org)

---

## 📝 Next Steps After MVP

Once Option A works:
1. Test end-to-end: two phones, tap-to-target payment
2. Add error handling and user feedback
3. Polish UI/UX
4. Add Option B (Stripe Terminal) when you upgrade Apple Developer account

---

## 🆘 Need Help?

- Check server logs: `npm run dev` output
- Check Xcode console for iOS errors
- Verify database: `psql gotchu -c "SELECT * FROM payment_sessions;"`
- Test API endpoints with `curl` or Postman

