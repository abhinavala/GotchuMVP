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
    const r = await query( // Query session by EID
      `SELECT ps.id as sid, ps.amount_cents, ps.exp_at, u.email
       FROM session_eids se
       JOIN payment_sessions ps ON se.session_id = ps.id
       JOIN users u ON ps.payee_id = u.id
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
    res.json({ // Return session data
      sid: r.rows[0].sid, // Session ID
      amount_cents: Number(r.rows[0].amount_cents), // Convert bigint to number
      payee_display: { name: r.rows[0].email.split("@")[0] }, // Extract name from email
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
      "SELECT id, payee_id, amount_cents, status, exp_at FROM payment_sessions WHERE id = $1",
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
    if (userId === s.payee_id) { // Check if user trying to pay themselves
      return res.status(400).json({ error: "cannot pay self" }); // Return 400 if self-payment
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
