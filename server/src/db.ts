import { Pool } from "pg"; // Import PostgreSQL connection pool

export const pool = new Pool({ // Create connection pool instance
  connectionString: process.env.DATABASE_URL, // Use DATABASE_URL from environment
}); // End pool config

export const query = async (sql: string, params?: any[]) => { // Async function to execute SQL queries
  const result = await pool.query(sql, params); // Execute query with optional parameters
  return result; // Return query result
}; // End query function
