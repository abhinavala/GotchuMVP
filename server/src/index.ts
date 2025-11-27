import express from "express"; // Import Express web framework
import morgan from "morgan"; // Import HTTP request logger middleware
import cors from "cors"; // Import CORS middleware for cross-origin requests
import dotenv from "dotenv"; // Import environment variable loader
import { query } from "./db"; // Import database query function
import { signDev, requireAuth } from "./auth"; // Import JWT auth functions
import { postTransfer } from "./ledger"; // Import double-entry ledger transfer function
import { newEID } from "./eid"; // Import EID generator function
import QRCode from "qrcode"; // Import QR code generator library

dotenv.config(); // Load environment variables from .env file

const app = express(); // Create Express application instance
app.use(cors()); // Enable CORS for all routes
app.use(express.json()); // Parse JSON request bodies
app.use(morgan("dev")); // Log HTTP requests in development format

// Health check
app.get("/health", (_, res) => res.send("OK")); // Health check endpoint returns "OK"

// Dev login
app.post("/auth/dev-login", async (req, res) => { // Dev login endpoint handler
  const { email } = req.body; // Extract email from request body
  if (!email) { // Check if email is provided
    return res.status(400).json({ error: "email required" }); // Return 400 if missing
  } // End if
  try { // Begin try block
    const r = await query("SELECT id FROM users WHERE email = $1", [email]); // Query user by email
    if (!r.rows.length) { // Check if user exists
      return res.status(404).json({ error: "not found" }); // Return 404 if not found
    } // End if
    res.json({ // Return success response
      token: signDev(r.rows[0].id), // Generate JWT token for user
      user_id: r.rows[0].id, // Include user ID in response
    }); // End response
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End dev login handler

// Wallet endpoints
app.get("/wallet/me", requireAuth, async (req, res) => { // Get wallet endpoint (requires auth)
  try { // Begin try block
    const userId = (req as any).userId; // Extract user ID from JWT token
    const w = await query( // Query wallet account
      "SELECT id, available_cents FROM wallet_accounts WHERE user_id = $1",
      [userId] // Pass user ID as parameter
    ); // End query
    if (!w.rows.length) { // Check if wallet exists
      return res.status(404).json({ error: "wallet not found" }); // Return 404 if not found
    } // End if
    const wallet = w.rows[0]; // Get first wallet row
    const h = await query( // Query recent ledger entries
      `SELECT type, direction, amount_cents, ref_type, ref_id, created_at
       FROM ledger_entries
       WHERE wallet_id = $1
       ORDER BY created_at DESC
       LIMIT 20`, // Select last 20 entries
      [wallet.id] // Pass wallet ID as parameter
    ); // End query
    res.json({ // Return wallet data
      wallet_id: wallet.id, // Include wallet ID
      available_cents: Number(wallet.available_cents), // Convert bigint to number
      recent: h.rows, // Include recent transactions
    }); // End response
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End wallet endpoint

// Session endpoints
app.post("/sessions/create", requireAuth, async (req, res) => { // Create payment session endpoint
  try { // Begin try block
    const { amount_cents, split_mode = "single", max_payers = 1 } = req.body; // Extract request body
    if (!Number.isInteger(amount_cents) || amount_cents <= 0) { // Validate amount
      return res.status(400).json({ error: "invalid amount" }); // Return 400 if invalid
    } // End if
    const exp = new Date(Date.now() + 300_000); // Set expiration to 5 minutes from now
    const userId = (req as any).userId; // Extract user ID from JWT token
    const ins = await query( // Insert new payment session
      `INSERT INTO payment_sessions (payee_id, amount_cents, split_mode, max_payers, exp_at, status)
       VALUES ($1, $2, $3, $4, $5, 'ADVERTISING')
       RETURNING id`, // Return session ID
      [userId, amount_cents, split_mode, max_payers, exp] // Pass parameters
    ); // End query
    const sid = ins.rows[0].id; // Get session ID from result
    const eid = newEID(); // Generate new EID
    await query("INSERT INTO session_eids (session_id, eid) VALUES ($1, $2)", [ // Insert EID mapping
      sid, // Session ID
      eid, // EID string
    ]); // End query
    res.json({ sid, eid, exp_at: exp.toISOString() }); // Return session data
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End create session handler

app.post("/sessions/resolve", async (req, res) => { // Resolve EID to session endpoint
  try { // Begin try block
    const { eid } = req.body; // Extract EID from request body
    if (!eid) { // Check if EID is provided
      return res.status(400).json({ error: "eid required" }); // Return 400 if missing
    } // End if
    const r = await query( // Query session by EID (handle both pull and push payments)
      `SELECT ps.id as sid, ps.amount_cents, ps.exp_at, ps.payer_id, ps.status,
              payee_user.email as payee_email, payer_user.email as payer_email
       FROM session_eids se
       JOIN payment_sessions ps ON se.session_id = ps.id
       JOIN users payee_user ON ps.payee_id = payee_user.id
       LEFT JOIN users payer_user ON ps.payer_id = payer_user.id
       WHERE se.eid = $1
       ORDER BY se.rotated_at DESC
       LIMIT 1`, // Get most recent EID mapping
      [eid] // Pass EID as parameter
    ); // End query
    if (!r.rows.length) { // Check if session found
      return res.status(404).json({ error: "not found" }); // Return 404 if not found
    } // End if
    if (new Date(r.rows[0].exp_at) < new Date()) { // Check if session expired
      return res.status(410).json({ error: "expired" }); // Return 410 if expired
    } // End if
    const row = r.rows[0]; // Get row
    // For push payments (payer_id set), show payee info (who to pay to)
    // For pull payments (payer_id null), show payee info (who is requesting)
    res.json({ // Return session data
      sid: row.sid, // Session ID
      amount_cents: Number(row.amount_cents), // Convert bigint to number
      status: row.status, // Session status
      payee_display: { name: row.payee_email.split("@")[0] }, // Extract name from email
      payer_display: row.payer_email ? { name: row.payer_email.split("@")[0] } : undefined, // Payer info if push payment
    }); // End response
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End resolve handler

app.post("/sessions/lock", requireAuth, async (req, res) => { // Lock session endpoint
  try { // Begin try block
    const { sid } = req.body; // Extract session ID from request body
    if (!sid) { // Check if SID is provided
      return res.status(400).json({ error: "sid required" }); // Return 400 if missing
    } // End if
    const r = await query( // Query session status
      "SELECT status, exp_at FROM payment_sessions WHERE id = $1",
      [sid] // Pass session ID as parameter
    ); // End query
    if (!r.rows.length) { // Check if session exists
      return res.status(404).json({ error: "not found" }); // Return 404 if not found
    } // End if
    if (new Date(r.rows[0].exp_at) < new Date()) { // Check if session expired
      return res.status(410).json({ error: "expired" }); // Return 410 if expired
    } // End if
    if (!["CREATED", "ADVERTISING"].includes(r.rows[0].status)) { // Check if session can be locked
      return res.status(409).json({ error: "busy" }); // Return 409 if already locked/paid
    } // End if
    await query("UPDATE payment_sessions SET status = 'LOCKED' WHERE id = $1", [ // Update session status
      sid, // Pass session ID
    ]); // End query
    res.json({ ok: true }); // Return success
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End lock handler

// Push payment endpoints (sender-initiated)
app.post("/sessions/create-offer", requireAuth, async (req, res) => { // Create payment offer (sender-initiated)
  try { // Begin try block
    const { payee_id, amount_cents } = req.body; // Extract request body
    if (!payee_id) { // Check if payee_id is provided
      return res.status(400).json({ error: "payee_id required" }); // Return 400 if missing
    } // End if
    if (!Number.isInteger(amount_cents) || amount_cents <= 0) { // Validate amount
      return res.status(400).json({ error: "invalid amount" }); // Return 400 if invalid
    } // End if
    const exp = new Date(Date.now() + 300_000); // Set expiration to 5 minutes from now
    const userId = (req as any).userId; // Extract user ID from JWT token (this is the payer)
    if (userId === payee_id) { // Check if user trying to pay themselves
      return res.status(400).json({ error: "cannot pay self" }); // Return 400 if self-payment
    } // End if
    // Verify payee exists
    const payeeCheck = await query("SELECT id FROM users WHERE id = $1", [payee_id]); // Check payee exists
    if (!payeeCheck.rows.length) { // Check if payee found
      return res.status(404).json({ error: "payee not found" }); // Return 404 if not found
    } // End if
    const ins = await query( // Insert new payment session with PENDING_ACCEPTANCE status
      `INSERT INTO payment_sessions (payee_id, payer_id, amount_cents, split_mode, max_payers, exp_at, status)
       VALUES ($1, $2, $3, 'single', 1, $4, 'PENDING_ACCEPTANCE')
       RETURNING id`, // Return session ID
      [payee_id, userId, amount_cents, exp] // Pass parameters
    ); // End query
    const sid = ins.rows[0].id; // Get session ID from result
    const eid = newEID(); // Generate new EID
    await query("INSERT INTO session_eids (session_id, eid) VALUES ($1, $2)", [ // Insert EID mapping
      sid, // Session ID
      eid, // EID string
    ]); // End query
    res.json({ sid, eid, exp_at: exp.toISOString() }); // Return session data
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End create offer handler

app.get("/sessions/pending-offers", requireAuth, async (req, res) => { // Get pending payment offers for receiver
  try { // Begin try block
    const userId = (req as any).userId; // Extract user ID from JWT token
    const offers = await query( // Query pending offers where user is payee
      `SELECT ps.id as sid, ps.amount_cents, ps.exp_at, ps.created_at, u.email as payer_email
       FROM payment_sessions ps
       JOIN users u ON ps.payer_id = u.id
       WHERE ps.payee_id = $1 AND ps.status = 'PENDING_ACCEPTANCE'
       AND ps.exp_at > NOW()
       ORDER BY ps.created_at DESC`, // Get pending offers
      [userId] // Pass user ID as parameter
    ); // End query
    res.json({ // Return offers
      offers: offers.rows.map((row) => ({ // Map rows to response format
        sid: row.sid, // Session ID
        amount_cents: Number(row.amount_cents), // Convert bigint to number
        payer_display: { name: row.payer_email.split("@")[0] }, // Extract name from email
        exp_at: row.exp_at, // Expiration time
        created_at: row.created_at, // Creation time
      })), // End map
    }); // End response
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End pending offers handler

app.post("/sessions/accept-offer", requireAuth, async (req, res) => { // Accept payment offer (receiver accepts)
  try { // Begin try block
    const { sid } = req.body; // Extract session ID from request body
    if (!sid) { // Check if SID is provided
      return res.status(400).json({ error: "sid required" }); // Return 400 if missing
    } // End if
    const userId = (req as any).userId; // Extract user ID from JWT token
    const r = await query( // Query session
      "SELECT status, exp_at, payee_id, payer_id FROM payment_sessions WHERE id = $1",
      [sid] // Pass session ID as parameter
    ); // End query
    if (!r.rows.length) { // Check if session exists
      return res.status(404).json({ error: "not found" }); // Return 404 if not found
    } // End if
    if (r.rows[0].payee_id !== userId) { // Check if user is the payee
      return res.status(403).json({ error: "not authorized" }); // Return 403 if not authorized
    } // End if
    if (new Date(r.rows[0].exp_at) < new Date()) { // Check if session expired
      return res.status(410).json({ error: "expired" }); // Return 410 if expired
    } // End if
    if (r.rows[0].status !== "PENDING_ACCEPTANCE") { // Check if session is pending
      return res.status(409).json({ error: "offer already processed" }); // Return 409 if already processed
    } // End if
    // Get EID for this session
    const eidResult = await query( // Query EID
      "SELECT eid FROM session_eids WHERE session_id = $1 ORDER BY rotated_at DESC LIMIT 1",
      [sid] // Pass session ID
    ); // End query
    const eid = eidResult.rows[0]?.eid; // Get EID
    // Accept offer: change to ADVERTISING and lock immediately (sender will complete payment)
    await query("UPDATE payment_sessions SET status = 'LOCKED' WHERE id = $1", [ // Update session status to LOCKED (ready for sender to pay)
      sid, // Pass session ID
    ]); // End query
    res.json({ ok: true, eid, sid }); // Return success with EID
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End accept offer handler

app.get("/users/list", requireAuth, async (req, res) => { // List all users (for sender to see who to send to)
  try { // Begin try block
    const userId = (req as any).userId; // Extract user ID from JWT token
    const users = await query( // Query all users except self
      "SELECT id, email FROM users WHERE id != $1 ORDER BY email",
      [userId] // Pass user ID as parameter
    ); // End query
    res.json({ // Return users
      users: users.rows.map((row) => ({ // Map rows to response format
        id: row.id, // User ID
        email: row.email, // Email
        display_name: row.email.split("@")[0], // Extract name from email
      })), // End map
    }); // End response
  } catch (e: any) { // Catch database errors
    res.status(500).json({ error: e.message }); // Return 500 with error message
  } // End catch
}); // End list users handler

app.post("/wallet/send", requireAuth, async (req, res) => { // Send payment endpoint
  try { // Begin try block
    const { sid } = req.body; // Extract session ID from request body
    const idempotencyKey = req.headers["idempotency-key"] as string; // Get idempotency key from header

    if (!sid) { // Check if SID is provided
      return res.status(400).json({ error: "sid required" }); // Return 400 if missing
    } // End if

    const userId = (req as any).userId; // Extract user ID from JWT token

    // Check idempotency
    if (idempotencyKey) { // If idempotency key provided
      const existing = await query( // Check if key already used
        "SELECT * FROM idempotency_keys WHERE key = $1",
        [idempotencyKey] // Pass key as parameter
      ); // End query
      if (existing.rows.length) { // If key exists
        return res.status(409).json({ error: "duplicate request" }); // Return 409 for duplicate
      } // End if
    } // End if

    const sr = await query( // Query payment session
      "SELECT id, payee_id, payer_id, amount_cents, status, exp_at FROM payment_sessions WHERE id = $1",
      [sid] // Pass session ID as parameter
    ); // End query
    if (!sr.rows.length) { // Check if session exists
      return res.status(404).json({ error: "session not found" }); // Return 404 if not found
    } // End if
    const s = sr.rows[0]; // Get session row
    if (new Date(s.exp_at) < new Date()) { // Check if session expired
      return res.status(410).json({ error: "expired" }); // Return 410 if expired
    } // End if
    if (!["LOCKED", "CREATED", "ADVERTISING"].includes(s.status)) { // Check if session can be paid
      return res.status(409).json({ error: "busy/paid" }); // Return 409 if already paid
    } // End if
    // For push payments (payer_id set), only the payer can pay
    // For pull payments (payer_id null), anyone except payee can pay
    if (s.payer_id) { // Push payment (sender-initiated)
      if (userId !== s.payer_id) { // Check if user is the payer
        return res.status(403).json({ error: "only payer can complete this payment" }); // Return 403 if not payer
      } // End if
    } else { // Pull payment (receiver-initiated)
      if (userId === s.payee_id) { // Check if user trying to pay themselves
        return res.status(400).json({ error: "cannot pay self" }); // Return 400 if self-payment
      } // End if
    } // End if

    const pW = ( // Query payer wallet
      await query("SELECT id FROM wallet_accounts WHERE user_id = $1", [userId])
    ).rows[0]; // Get payer wallet row
    const rW = ( // Query receiver wallet
      await query("SELECT id FROM wallet_accounts WHERE user_id = $1", [
        s.payee_id, // Pass payee user ID
      ])
    ).rows[0]; // Get receiver wallet row

    await postTransfer({ // Execute double-entry transfer
      fromWalletId: pW.id, // Payer wallet ID
      toWalletId: rW.id, // Receiver wallet ID
      amount_cents: Number(s.amount_cents), // Convert bigint to number
      ref_type: "PAYMENT_SESSION", // Reference type
      ref_id: s.id, // Session ID as reference
    }); // End transfer
    await query("UPDATE payment_sessions SET status = 'PAID' WHERE id = $1", [ // Update session to paid
      sid, // Pass session ID
    ]); // End query

    if (idempotencyKey) { // If idempotency key provided
      await query( // Store idempotency key
        "INSERT INTO idempotency_keys (key, user_id, route, ref) VALUES ($1, $2, $3, $4)",
        [idempotencyKey, userId, "/wallet/send", sid] // Pass parameters
      ); // End query
    } // End if

    const nb = ( // Query new balance
      await query(
        "SELECT available_cents FROM wallet_accounts WHERE id = $1",
        [pW.id] // Pass payer wallet ID
      )
    ).rows[0].available_cents; // Get available cents
    res.json({ ok: true, new_balance_cents: Number(nb) }); // Convert bigint to number and return
  } catch (e: any) { // Catch transfer errors
    res.status(400).json({ error: e.message }); // Return 400 with error message
  } // End catch
}); // End send payment handler

// QR deep link fallback
app.get("/deeplink/pay", async (req, res) => { // QR code generation endpoint
  try { // Begin try block
    const { sid } = req.query as any; // Extract session ID from query params
    if (!sid) { // Check if SID is provided
      return res.status(400).json({ error: "sid required" }); // Return 400 if missing
    } // End if
    const link = `gotchu://pay?sid=${sid}`; // Create deep link URL
    const img = await QRCode.toDataURL(link); // Generate QR code as data URL
    res.setHeader("Content-Type", "text/html"); // Set response content type
    res.send(` // Send HTML page with QR code
      <!DOCTYPE html>
      <html>
        <head>
          <title>Gotchu Payment</title>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { font-family: -apple-system, sans-serif; text-align: center; padding: 20px; }
            a { color: #007AFF; text-decoration: none; font-size: 18px; display: block; margin: 20px 0; }
            img { margin: 20px auto; display: block; }
          </style>
        </head>
        <body>
          <h3>Open in Gotchu to pay</h3>
          <a href="${link}">${link}</a>
          <img src="${img}" width="220" alt="QR Code"/>
        </body>
      </html>
    `); // End HTML
  } catch (e: any) { // Catch QR generation errors
    res.status(500).json({ error: "failed to generate QR" }); // Return 500 with error
  } // End catch
}); // End QR handler

const PORT = Number(process.env.PORT) || 3001; // Get port from env or default to 3001
const HOST = process.env.HOST || "0.0.0.0"; // Get host from env or default to all interfaces
app.listen(PORT, HOST, () => { // Start server listening
  console.log(`🚀 Gotchu API running on http://${HOST}:${PORT}`); // Log server URL
  console.log(`📊 Health check: http://localhost:${PORT}/health`); // Log health check URL
  console.log(`🌐 Network access: http://172.31.165.144:${PORT} (or your Mac's IP)`); // Log network access info
}); // End listen callback
