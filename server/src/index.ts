import express from "express";
import morgan from "morgan";
import cors from "cors";
import dotenv from "dotenv";
import { query } from "./db";
import { signDev, requireAuth } from "./auth";
import { postTransfer } from "./ledger";
import { newEID } from "./eid";
import QRCode from "qrcode";

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());
app.use(morgan("dev"));

// Health check
app.get("/health", (_, res) => res.send("OK"));

// Dev login
app.post("/auth/dev-login", async (req, res) => {
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ error: "email required" });
  }
  try {
    const r = await query("SELECT id FROM users WHERE email = $1", [email]);
    if (!r.rows.length) {
      return res.status(404).json({ error: "not found" });
    }
    res.json({
      token: signDev(r.rows[0].id),
      user_id: r.rows[0].id,
    });
  } catch (e: any) {
    res.status(500).json({ error: e.message });
  }
});

// Wallet endpoints
app.get("/wallet/me", requireAuth, async (req, res) => {
  try {
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
      available_cents: Number(wallet.available_cents), // Convert bigint to number
      recent: h.rows,
    });
  } catch (e: any) {
    res.status(500).json({ error: e.message });
  }
});

// Session endpoints
app.post("/sessions/create", requireAuth, async (req, res) => {
  try {
    const { amount_cents, split_mode = "single", max_payers = 1 } = req.body;
    if (!Number.isInteger(amount_cents) || amount_cents <= 0) {
      return res.status(400).json({ error: "invalid amount" });
    }
    const exp = new Date(Date.now() + 300_000); // 5 minutes TTL (increased for testing)
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
  } catch (e: any) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/sessions/resolve", async (req, res) => {
  try {
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
      amount_cents: Number(r.rows[0].amount_cents), // Convert bigint to number
      payee_display: { name: r.rows[0].email.split("@")[0] },
    });
  } catch (e: any) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/sessions/lock", requireAuth, async (req, res) => {
  try {
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
  } catch (e: any) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/wallet/send", requireAuth, async (req, res) => {
  try {
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

    await postTransfer({
      fromWalletId: pW.id,
      toWalletId: rW.id,
      amount_cents: Number(s.amount_cents), // Convert bigint to number
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
    res.json({ ok: true, new_balance_cents: Number(nb) }); // Convert bigint to number
  } catch (e: any) {
    res.status(400).json({ error: e.message });
  }
});

// QR deep link fallback
app.get("/deeplink/pay", async (req, res) => {
  try {
    const { sid } = req.query as any;
    if (!sid) {
      return res.status(400).json({ error: "sid required" });
    }
    const link = `gotchu://pay?sid=${sid}`;
    const img = await QRCode.toDataURL(link);
    res.setHeader("Content-Type", "text/html");
    res.send(`
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
    `);
  } catch (e: any) {
    res.status(500).json({ error: "failed to generate QR" });
  }
});

const PORT = process.env.PORT || 3001;
const HOST = process.env.HOST || "0.0.0.0"; // Bind to all interfaces
app.listen(PORT, HOST, () => {
  console.log(`🚀 Gotchu API running on http://${HOST}:${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`🌐 Network access: http://172.31.165.144:${PORT} (or your Mac's IP)`);
});

