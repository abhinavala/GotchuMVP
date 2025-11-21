# Gotchu MVP - Next Steps Roadmap

## ✅ What's Working Now
- ✅ User authentication (JWT login)
- ✅ Wallet balance and history
- ✅ Session creation with EID
- ✅ BLE advertising and scanning (basic)
- ✅ Manual EID resolve and payment
- ✅ Money transfers between wallets
- ✅ Double-entry ledger system

---

## 🎯 Priority 1: RSSI Gating & Auto-Resolve (Tap-to-Target)

**Current State:** All discovered EIDs are shown, user manually selects

**Goal:** Only show EIDs when phones are very close, automatically resolve when detected

**What to Build:**
1. **RSSI Tracking**
   - Track RSSI (signal strength) for each discovered device
   - Keep rolling window of last 5 samples per device
   - Only surface EID if ≥4/5 samples are above threshold (-60 dBm)

2. **Automatic Resolve**
   - When EID passes RSSI gate, automatically call `resolveCurrent()`
   - Show payment sheet automatically (no manual tap needed)
   - This creates the "tap-to-target" experience

3. **Proximity Feedback**
   - Show visual/haptic feedback when device is close enough
   - Update status text: "Too far" → "Getting closer" → "Ready to pay"

**Impact:** This is the core "tap the tops of phones together" feature

**Estimated Time:** 2-3 hours

---

## 🎯 Priority 2: Production UI Screens

**Current State:** Single dev panel with all features

**Goal:** Separate, polished screens for each flow

**What to Build:**

1. **Request Screen** (Receiver)
   - Clean amount input
   - Create session button
   - Session status with countdown timer
   - QR code option
   - BLE advertising status

2. **Pay Sheet** (Payer)
   - Appears automatically when session detected
   - Shows amount and payee name
   - Large "Pay" button
   - Cancel option

3. **Wallet Screen**
   - Current balance (large, prominent)
   - Recent transactions list
   - Pull-to-refresh

4. **History Screen**
   - Full transaction history
   - Filter by type (sent/received)
   - Transaction details

**Impact:** Makes app feel production-ready, better UX

**Estimated Time:** 3-4 hours

---

## 🎯 Priority 3: QR Code Fallback

**Current State:** Server has `/deeplink/pay?sid=...` endpoint, but app doesn't use it

**Goal:** Receiver can show QR code, payer scans to open payment

**What to Build:**

1. **QR Generation** (Receiver)
   - Generate QR code from session SID
   - Display QR code on screen
   - Deep link format: `gotchu://pay?sid=...`

2. **Deep Link Handling** (Payer)
   - Handle `gotchu://pay?sid=...` URL scheme
   - Extract SID from URL
   - Automatically resolve and show pay sheet

3. **QR Scanner** (Payer)
   - Camera-based QR code scanner
   - Scan QR → extract SID → resolve → pay

**Impact:** Works when BLE doesn't work, or for remote payments

**Estimated Time:** 2-3 hours

---

## 🎯 Priority 4: Better Error Handling & UX

**Current State:** Basic error alerts

**Goal:** Clear, actionable error messages and better feedback

**What to Build:**

1. **Session Expiration Countdown**
   - Show countdown timer: "Expires in 4:32"
   - Auto-refresh or warn when expiring soon
   - Handle expired sessions gracefully

2. **Better Error Messages**
   - "Insufficient funds" → "You need $X more"
   - "Session expired" → "Request a new payment"
   - "Busy" → "Someone else is paying this request"

3. **Retry Logic**
   - Automatic retry for network errors
   - Manual retry button for failed operations

4. **Loading States**
   - Better loading indicators
   - Progress feedback for multi-step operations

**Impact:** Better user experience, fewer support questions

**Estimated Time:** 2 hours

---

## 🎯 Priority 5: Payment Confirmation Flow

**Current State:** Payment happens immediately after "Lock & Pay"

**Goal:** Show confirmation screen before finalizing

**What to Build:**

1. **Confirmation Sheet**
   - Shows amount, payee name, your balance
   - "Confirm Payment" button
   - Cancel option

2. **Success Screen**
   - Confirmation that payment succeeded
   - Updated balances
   - "Done" button to dismiss

**Impact:** Prevents accidental payments, better UX

**Estimated Time:** 1-2 hours

---

## 🎯 Priority 6: Testing & Edge Cases

**What to Test:**

1. **Crowd Safety**
   - Multiple payers trying to pay same session
   - Only one should succeed (locking works)

2. **Network Edge Cases**
   - Payment succeeds but network fails before response
   - Idempotency prevents double-charge

3. **BLE Edge Cases**
   - Multiple sessions advertising at once
   - RSSI gating prevents wrong selection

4. **Session Edge Cases**
   - Expired sessions can't be paid
   - Already-paid sessions show "busy"

**Impact:** Ensures reliability in real-world use

**Estimated Time:** 2-3 hours

---

## 📊 Recommended Order

**For MVP Completion:**

1. **RSSI Gating & Auto-Resolve** (Priority 1)
   - Core "tap-to-target" feature
   - Makes the app feel magical

2. **Production UI Screens** (Priority 2)
   - Makes app feel complete
   - Better user experience

3. **QR Code Fallback** (Priority 3)
   - Important backup when BLE fails
   - Easy to implement

4. **Better Error Handling** (Priority 4)
   - Polish and reliability

5. **Payment Confirmation** (Priority 5)
   - Safety feature

6. **Testing** (Priority 6)
   - Final polish

---

## 🚀 Quick Wins (Can Do Anytime)

- Add haptic feedback on successful payment
- Add session expiration countdown
- Improve error messages
- Add pull-to-refresh on wallet
- Add transaction detail view

---

## 💡 Future Enhancements (Post-MVP)

- Android app
- Group splits (multiple payers)
- EID rotation for privacy
- Push notifications
- Bank account linking
- Transaction search/filtering
- Analytics dashboard

---

## 🎯 What Should We Build Next?

**Recommendation:** Start with **Priority 1 (RSSI Gating & Auto-Resolve)** because:
- It's the core differentiating feature
- Makes the app feel complete
- Relatively straightforward to implement
- High impact on user experience

**Alternative:** If you want to polish the UI first, start with **Priority 2 (Production UI Screens)**

Let me know which one you'd like to tackle first!

