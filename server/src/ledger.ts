import { pool } from "./db"; // Import database connection pool

export async function postTransfer(o: { // Async function for double-entry ledger transfer
  fromWalletId: string; // Source wallet ID
  toWalletId: string; // Destination wallet ID
  amount_cents: number; // Transfer amount in cents
  ref_type: string; // Reference type (e.g., "PAYMENT_SESSION")
  ref_id: string; // Reference ID
}) { // End function parameters
  const client = await pool.connect(); // Get database client from pool
  try { // Begin try block
    await client.query("BEGIN"); // Start database transaction

    // Lock and check sender balance
    const fw = await client.query( // Query sender wallet with row lock
      "SELECT available_cents FROM wallet_accounts WHERE id = $1 FOR UPDATE",
      [o.fromWalletId] // Pass sender wallet ID
    ); // End query
    if (!fw.rows.length) { // Check if wallet exists
      throw new Error("from wallet not found"); // Throw error if not found
    } // End if
    const availableCents = Number(fw.rows[0].available_cents); // Convert bigint string to number
    if (availableCents < o.amount_cents) { // Check if sufficient funds
      throw new Error("insufficient funds"); // Throw error if insufficient
    } // End if

    // Update balances
    await client.query( // Debit sender wallet
      "UPDATE wallet_accounts SET available_cents = available_cents - $1 WHERE id = $2",
      [o.amount_cents, o.fromWalletId] // Pass amount and wallet ID
    ); // End query
    await client.query( // Credit receiver wallet
      "UPDATE wallet_accounts SET available_cents = available_cents + $1 WHERE id = $2",
      [o.amount_cents, o.toWalletId] // Pass amount and wallet ID
    ); // End query

    // Insert ledger entries (double-entry)
    await client.query( // Insert debit and credit ledger entries
      `INSERT INTO ledger_entries (wallet_id, type, direction, amount_cents, ref_type, ref_id)
       VALUES ($1, 'SEND_P2P', 'DEBIT', $3, $4, $5),
              ($2, 'RECEIVE_P2P', 'CREDIT', $3, $4, $5)`, // Double-entry: debit sender, credit receiver
      [o.fromWalletId, o.toWalletId, o.amount_cents, o.ref_type, o.ref_id] // Pass parameters
    ); // End query

    await client.query("COMMIT"); // Commit transaction
  } catch (e) { // Catch any errors
    await client.query("ROLLBACK"); // Rollback transaction on error
    throw e; // Re-throw error
  } finally { // Always execute
    client.release(); // Release client back to pool
  } // End finally
} // End postTransfer
