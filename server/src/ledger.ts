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
    const availableCents = Number(fw.rows[0].available_cents); // Convert bigint string to number
    if (availableCents < o.amount_cents) {
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

    // Insert ledger entries (double-entry)
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

