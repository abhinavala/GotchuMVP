# ✅ Your Action Items - Step by Step

## What I Need From You (In Order)

---

### Step 1: Install Server Dependencies ⏱️ 2 minutes

**What to do:**
```bash
cd /Users/abhinavala/Desktop/gotchu/server ✅
npm install ✅
```

**What I need:**
- ✅ Confirmation that `npm install` completed without errors
- ✅ Or tell me if you see any errors

**Verify:** You should see `node_modules/` folder created

---

### Step 2: Set Up Database ⏱️ 10 minutes

**Choose ONE option:**

#### Option A: Local Postgres (if you have Postgres installed)

**What to do:**
```bash
# Create database
createdb gotchu

# Load schema
psql gotchu < server/docs/schema.sql

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

**What I need:**
- ✅ Your Postgres connection string (format: `postgres://user:password@localhost:5432/gotchu`)
- ✅ Confirmation that schema loaded successfully
- ✅ Or tell me if you get any errors

#### Option B: Neon Cloud (if you don't have Postgres)

**What to do:**
1. Go to https://neon.tech ✅
2. Sign up (free) ✅
3. Create a new project ✅
4. Copy the connection string (looks like: `postgres:// user:pass@ep-xxx.us-east-2.aws.neon.tech/neondb?sslmode=require`) ✅

here is the neon connection string:
psql 'postgresql://neondb_owner:npg_0Juqdgair8bl@ep-bold-paper-a4izi4s6-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require'

**⚠️ Important:** 
- **Don't enable any special "Neon auth" features** - just use the default connection string
- The connection string already includes authentication (username/password)
- Our app uses JWT for user authentication (separate from database auth)

**What I need:**
- ✅ The connection string from Neon dashboard
- ✅ I'll help you load the schema once you have it

---

### Step 3: Create Environment File ⏱️ 2 minutes

**What to do:**

Create file: `/Users/abhinavala/Desktop/gotchu/server/.env`

**What I need from you:**

I gave you the info you need, make the .env file

1. **Database connection string** (from Step 2)
db connections string: psql 'postgresql://neondb_owner:npg_0Juqdgair8bl@ep-bold-paper-a4izi4s6-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require'
2. **A random JWT secret** (at least 32 characters)
jwt secret: 406d1e643f8bd119a9878ff7f3705751a69d16eb40dfdac7bc29d9cf155ba103

**Example `.env` file:**
```
PORT=3001
DATABASE_URL=postgres://YOUR_CONNECTION_STRING_HERE
JWT_SECRET=YOUR_RANDOM_32_CHAR_SECRET_HERE
APP_BASE_URL=http://localhost:3001
```

**Quick way to generate JWT secret:**
```bash
openssl rand -hex 32
```

**What I need:**
- ✅ Confirmation that `.env` file is created
- ✅ Or tell me if you need help with any of these values

---

### Step 4: Test Server ⏱️ 3 minutes

**What to do:**
```bash
cd /Users/abhinavala/Desktop/gotchu/server
npm run dev
```

**What I need:**
- ✅ Tell me if server starts successfully (you should see: `🚀 Gotchu API running on http://localhost:3001`)
- ✅ Or tell me what error message you see (if any)

**Then test it:**
```bash
# In a new terminal
curl http://localhost:3001/health
```

**What I need:**
- ✅ Tell me if you see "OK" response
- ✅ Or tell me what error you get

---

### Step 5: Test Database Connection ⏱️ 2 minutes

**What to do:**
```bash
curl -X POST http://localhost:3001/auth/dev-login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com"}'
```

**What I need:**
- ✅ Tell me if you get a response with `token` and `user_id`
- ✅ Or tell me what error you see

**If you get an error:**
- Share the exact error message
- I'll help you fix it

---

### Step 6: Configure iOS App in Xcode ⏱️ 10 minutes

**What to do:**

1. Open Xcode project:
   ```bash
   open /Users/abhinavala/Desktop/gotchu/mvp/GotchuMVP/GotchuMVP.xcodeproj
   ```

2. **Set Signing:**
   - Click on project name (left sidebar) → Select "GotchuMVP" target
   - Go to "Signing & Capabilities" tab
   - Under "Team": Select your Apple ID
   - Under "Bundle Identifier": Change to something unique like `com.yourname.gotchu`
   - ✅ Check "Automatically manage signing"

   

3. **Add Bluetooth Permission:**
   - Click on "Info" tab
   - Click the + button to add new key
   - Key: `Privacy - Bluetooth Always Usage Description`
   - Value: `Used to discover nearby pay requests.`

4. **Add URL Scheme:**
   - Still in "Info" tab
   - Expand "URL Types" section
   - Click + to add new URL Type
   - Identifier: `gotchu`
   - URL Schemes: `gotchu` (add this in the array)

5. **Add CoreBluetooth Framework:**
   - Go to "Build Phases" tab
   - Expand "Link Binary With Libraries"
   - Click + button
   - Search for "CoreBluetooth"
   - Add it

6. **Build:**
   - Press `Cmd+B` to build
   - Or Product → Build

**What I need:**
- ✅ Tell me if build succeeds
- ✅ Or share the exact error message if build fails

---

### Step 7: Test on Physical iPhone ⏱️ 5 minutes

**What to do:**

1. Connect your iPhone via USB
2. In Xcode, select your iPhone from the device dropdown (top toolbar)
3. Click Run button (▶️) or press `Cmd+R`
4. If prompted, trust your Mac on iPhone
5. App should install and launch

**What I need:**
- ✅ Tell me if app installs and launches successfully
- ✅ Or share any error messages you see

**Note:** With free Apple Developer account, you may need to:
- Go to iPhone Settings → General → VPN & Device Management
- Trust your developer certificate

---

## 🎯 Summary: What I Need From You

1. ✅ **Step 1:** Confirmation `npm install` worked
2. ✅ **Step 2:** Database connection string (or tell me if you need help setting up database)
3. ✅ **Step 3:** Confirmation `.env` file created with your values
4. ✅ **Step 4:** Confirmation server starts and `/health` works
5. ✅ **Step 5:** Confirmation login endpoint works
6. ✅ **Step 6:** Confirmation iOS app builds in Xcode
7. ✅ **Step 7:** Confirmation app runs on physical device

---

## 🚨 If You Get Stuck

**For any step, just tell me:**
- What step you're on
- What command you ran (or what you clicked)
- The exact error message you see (copy/paste it)

**I'll help you fix it immediately.**

---

## 📝 Quick Checklist

Print this out and check off as you go:

- [ ] Step 1: `npm install` completed
- [ ] Step 2: Database set up (local or Neon)
- [ ] Step 3: `.env` file created
- [ ] Step 4: Server runs (`npm run dev`)
- [ ] Step 5: `/health` returns "OK"
- [ ] Step 6: Login endpoint works
- [ ] Step 7: iOS app builds in Xcode
- [ ] Step 8: App runs on physical iPhone

---

**Start with Step 1 and let me know when you're done or if you hit any issues!** 🚀

