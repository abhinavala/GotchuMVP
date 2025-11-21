# 🚀 START HERE - Gotchu MVP Build Process

## ✅ What's Already Done

I've set up the **complete server structure** for you:

- ✅ Server directory structure
- ✅ All TypeScript source files (auth, wallet, sessions, ledger, QR)
- ✅ Database schema SQL file
- ✅ Package.json with all dependencies
- ✅ TypeScript configuration
- ✅ Complete API implementation

## 🎯 What You Need to Do Now (In Order)

### Step 1: Install Server Dependencies (2 min)

```bash
cd /Users/abhinavala/Desktop/gotchu/server
npm install
```

**Verify:** No errors, `node_modules/` folder appears

---

### Step 2: Set Up Database (10 min)

**Option A: Local Postgres**
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

**Option B: Neon (Cloud Postgres)**
1. Go to https://neon.tech
2. Create free account → Create project
3. Copy connection string
4. Use it in Step 3

**Verify:**
```bash
psql gotchu -c "SELECT u.email, w.available_cents FROM users u JOIN wallet_accounts w ON u.id = w.user_id;"
```
Should show 2 users with wallets.

---

### Step 3: Create Environment File (2 min)

```bash
cd /Users/abhinavala/Desktop/gotchu/server
```

Create `.env` file:
```bash
cat > .env << 'EOF'
PORT=3001
DATABASE_URL=postgres://user:password@localhost:5432/gotchu
JWT_SECRET=change_me_to_random_string_min_32_chars_long
APP_BASE_URL=http://localhost:3001
EOF
```

**⚠️ IMPORTANT:** 
- Replace `DATABASE_URL` with your actual Postgres connection string
- For Neon: Use the connection string from their dashboard
- Generate a random `JWT_SECRET` (at least 32 characters)

**Verify:** File exists: `ls -la .env`

---

### Step 4: Start Server (1 min)

```bash
npm run dev
```

**Verify:** 
- See message: `🚀 Gotchu API running on http://localhost:3001`
- Visit http://localhost:3001/health → Should see "OK"

---

### Step 5: Test API (3 min)

Open a new terminal and run:

```bash
# Test health
curl http://localhost:3001/health

# Test login
curl -X POST http://localhost:3001/auth/dev-login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com"}'

# Should return: {"token":"...", "user_id":"..."}
```

**Verify:** All commands return expected responses

---

### Step 6: Configure iOS App (10 min)

1. **Open Xcode Project:**
   ```bash
   open /Users/abhinavala/Desktop/gotchu/mvp/GotchuMVP/GotchuMVP.xcodeproj
   ```

2. **Set Signing:**
   - Select project → Target "GotchuMVP"
   - Signing & Capabilities tab
   - Team: Select your Apple ID (free account)
   - Bundle Identifier: `com.yourname.gotchu` (make it unique)
   - ✅ Check "Automatically manage signing"

3. **Add Bluetooth Permission:**
   - Select "Info" tab (or open Info.plist as source)
   - Add new key: `Privacy - Bluetooth Always Usage Description`
   - Value: `Used to discover nearby pay requests.`

4. **Add URL Scheme:**
   - Select "Info" tab
   - Expand "URL Types"
   - Click + to add new URL Type
   - Identifier: `gotchu`
   - URL Schemes: `gotchu`

5. **Add CoreBluetooth Framework:**
   - Select "Build Phases" tab
   - Expand "Link Binary With Libraries"
   - Click + → Add `CoreBluetooth.framework`

**Verify:** Project builds without errors (`Cmd+B`)

---

### Step 7: Test on Physical Device (5 min)

**⚠️ CRITICAL:** BLE only works on physical devices, NOT simulator!

1. Connect iPhone via USB
2. In Xcode, select your device from the device dropdown
3. Click Run (▶️) or press `Cmd+R`
4. App should install and launch

**Note:** With free Apple Developer account, builds expire after ~7 days. You'll need to reinstall from Xcode.

---

## 📱 iOS App Implementation (Next Phase)

The server is **100% ready**. Now you need to implement the iOS app:

1. **BLE Manager** - Advertise/scan for sessions
2. **API Client** - Call server endpoints
3. **UI Screens** - Request, Pay, Wallet, History views

See `BUILD_GUIDE.md` Phase 7-8 for detailed iOS implementation steps.

---

## 🐛 Troubleshooting

### Server won't start
- Check `.env` file exists and `DATABASE_URL` is correct
- Ensure Postgres is running: `pg_isready`
- Check port 3001 isn't in use: `lsof -i :3001`

### Database connection error
- Verify `DATABASE_URL` format: `postgres://user:pass@host:port/dbname`
- For Neon: Ensure connection string includes `?sslmode=require`
- Test connection: `psql "YOUR_DATABASE_URL" -c "SELECT 1;"`

### Xcode signing error
- Use your Apple ID as team (free account)
- Make bundle ID unique (add your name/org)
- Clean build folder: `Cmd+Shift+K` then rebuild

### BLE not working
- **Must test on physical device** (simulator doesn't support BLE)
- Check Info.plist has Bluetooth permission
- Ensure app is in foreground (background BLE is limited on free account)

---

## 📚 Documentation

- **`BUILD_GUIDE.md`** - Complete step-by-step guide with all code
- **`QUICK_START.md`** - Quick reference checklist
- **`server/README.md`** - Server-specific documentation

---

## ✅ Success Criteria

You'll know everything is working when:

1. ✅ Server runs: `http://localhost:3001/health` returns "OK"
2. ✅ Database has 2 test users with wallets
3. ✅ API login works: `/auth/dev-login` returns token
4. ✅ iOS app builds and runs on physical device
5. ✅ BLE permission prompt appears when app tries to use Bluetooth

---

## 🎯 Next Steps After Setup

Once server is running and iOS app builds:

1. Implement BLE advertising/scanning in iOS
2. Wire up API calls from iOS to server
3. Build UI screens (Request, Pay, Wallet, History)
4. Test end-to-end: two phones → tap-to-target → payment

---

## 💡 Pro Tips

- **Use your Mac's IP address** for iOS device testing (not `localhost`)
  - Find IP: `ifconfig | grep "inet " | grep -v 127.0.0.1`
  - Update API base URL in iOS app to `http://YOUR_IP:3001`

- **Keep server running** in one terminal while developing iOS app

- **Use Postman or curl** to test API endpoints before wiring up iOS

- **Test BLE on two physical devices** - you can't test tap-to-target with just one phone

---

## 🆘 Need Help?

1. Check server logs in terminal running `npm run dev`
2. Check Xcode console for iOS errors
3. Verify database: `psql gotchu -c "SELECT * FROM payment_sessions;"`
4. Test API with curl commands above

---

**You're all set! Start with Step 1 above.** 🚀

