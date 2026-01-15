import { Pool } from "pg"; // Import PostgreSQL connection pool

// Parse DATABASE_URL to ensure database name is correctly extracted
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  throw new Error("DATABASE_URL environment variable is not set");
}

// Parse connection string to extract database name explicitly
// This fixes issues where pg library might not parse the connection string correctly
const urlMatch = dbUrl.match(/postgres(ql)?:\/\/(?:([^:@]+)(?::([^@]+))?@)?([^:\/]+)(?::(\d+))?\/([^?]+)/);
let pool: Pool;

if (urlMatch) {
  const [, , user, password, host, port, database] = urlMatch;
  pool = new Pool({
    host: host || "localhost",
    port: port ? parseInt(port) : 5432,
    user: user || undefined,
    password: password || undefined,
    database: database || undefined,
  });
} else {
  // Fallback to connection string if parsing fails
  pool = new Pool({ connectionString: dbUrl });
}

export { pool };

export const query = async (sql: string, params?: any[]) => { // Async function to execute SQL queries
  const result = await pool.query(sql, params); // Execute query with optional parameters
  return result; // Return query result
}; // End query function
