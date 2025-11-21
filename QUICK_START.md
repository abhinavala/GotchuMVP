# Gotchu MVP Quick Start Checklist

## 🚀 What You Need to Do (In Order)

### 1. **Verify Prerequisites** (5 min)
```bash
node -v          # Should be 20+
npm -v           # Should be 9+
psql --version   # Should be 14+ (or use Neon cloud)
xcodebuild -version  # Should be 15+
```

### 2. **Set Up Database** (10 min)
- **Local:** `createdb gotchu` then `psql gotchu < server/docs/schema.sql`
- **Cloud (Neon):** Create project → copy connection string → update `.env`

### 3. **Bootstrap Server** (15 min)
```bash
cd server
npm install
npm run dev
```
- Visit `http://localhost:3001/health` → should see "OK"
- Test: `curl http://localhost:3001/health`

### 4. **Seed Test Data** (2 min)
```bash
psql gotchu -c "INSERT INTO users (email) VALUES ('alice@example.com'), ('bob@example.com');"
psql gotchu -c "INSERT INTO wallet_accounts (user_id) SELECT id FROM users;"
psql gotchu -c "UPDATE wallet_accounts SET available_cents = 10000 WHERE user_id IN (SELECT id FROM users WHERE email = 'alice@example.com');"
```

### 5. **Test API Endpoints** (5 min)
```bash
# Login
curl -X POST http://localhost:3001/auth/dev-login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com"}'

# Save the token, then:
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3001/wallet/me
```

### 6. **Configure iOS App** (10 min)
- Open `mvp/GotchuMVP/GotchuMVP.xcodeproj`
- Signing: Select your Apple ID (free account)
- Bundle ID: `com.yourname.gotchu`
- Info.plist: Add `NSBluetoothAlwaysUsageDescription` = "Used to discover nearby pay requests."
- URL Types: Add scheme `gotchu`
- Build: `Cmd+B` should succeed

### 7. **Test on Physical Device** (5 min)
- Connect iPhone via USB
- Select device in Xcode
- Run: `Cmd+R`
- **Note:** BLE only works on physical devices, not simulator

---

## ⚠️ Critical Configuration

### Server `.env` File
```
PORT=3001
DATABASE_URL=postgres://user:pass@localhost:5432/gotchu
JWT_SECRET=your_random_32_char_secret_here
APP_BASE_URL=http://localhost:3001
```

### iOS API Base URL
- For simulator: `http://localhost:3001`
- For physical device: `http://YOUR_MAC_IP:3001` (find with `ifconfig | grep inet`)

---

## 🎯 MVP Success Criteria

You'll know it works when:
1. ✅ Two phones can see each other via BLE
2. ✅ Receiver creates $0.50 session → Payer sees "Pay $0.50 to Alice?"
3. ✅ Payer confirms → Money moves instantly
4. ✅ Both wallets show updated balances
5. ✅ QR code fallback works when BLE is off

---

## 🐛 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| Server won't start | Check `DATABASE_URL` in `.env` |
| BLE not working | Test on physical device, not simulator |
| Can't connect from phone | Use Mac's IP address, not `localhost` |
| Xcode signing error | Use your Apple ID as team, unique bundle ID |
| Database error | Run schema.sql again, check connection string |

---

## 📋 Build Order Summary

1. **Backend First** (Phases 1-6)
   - Server → Database → Auth → Wallet → Sessions → QR

2. **Frontend Second** (Phases 7-8)
   - iOS setup → BLE implementation → UI screens

3. **Test End-to-End** (Phase 12)
   - Two phones → tap-to-target → payment completes

---

## ⏱️ Estimated Time

- **Backend setup:** 1-2 hours
- **iOS app setup:** 1-2 hours  
- **BLE integration:** 2-3 hours
- **Testing & polish:** 2-3 hours

**Total MVP:** ~6-10 hours

---

## 📚 Full Details

See `BUILD_GUIDE.md` for complete step-by-step instructions with code examples.

