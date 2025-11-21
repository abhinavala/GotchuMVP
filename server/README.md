# Gotchu Server

API server for Gotchu MVP - contactless P2P payments.

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Set Up Environment

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

Edit `.env`:
```
PORT=3001
DATABASE_URL=postgres://user:password@localhost:5432/gotchu
JWT_SECRET=your_random_32_char_secret_here
APP_BASE_URL=http://localhost:3001
```

### 3. Set Up Database

```bash
# Create database
createdb gotchu

# Load schema
psql gotchu < docs/schema.sql

# Seed test users
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

### 4. Run Server

```bash
npm run dev
```

Server will start on `http://localhost:3001`

### 5. Test

```bash
# Health check
curl http://localhost:3001/health

# Dev login
curl -X POST http://localhost:3001/auth/dev-login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com"}'
```

## API Endpoints

### Auth
- `POST /auth/dev-login` - Dev login (email → token)

### Wallet
- `GET /wallet/me` - Get wallet balance and history (requires auth)

### Sessions
- `POST /sessions/create` - Create payment session (requires auth)
- `POST /sessions/resolve` - Resolve EID to session details
- `POST /sessions/lock` - Lock session for payment (requires auth)

### Payments
- `POST /wallet/send` - Send payment for a session (requires auth)

### QR
- `GET /deeplink/pay?sid=...` - Generate QR code for payment

## Development

- `npm run dev` - Start dev server with hot reload
- `npm run build` - Build TypeScript to JavaScript
- `npm start` - Run production build

## Project Structure

```
server/
├── src/
│   ├── index.ts      # Main server file with all routes
│   ├── db.ts         # Database connection
│   ├── auth.ts       # JWT authentication
│   ├── ledger.ts     # Double-entry ledger transfers
│   └── eid.ts        # EID generator for BLE
├── docs/
│   └── schema.sql    # Database schema
├── package.json
├── tsconfig.json
└── .env              # Environment variables (not in git)
```

