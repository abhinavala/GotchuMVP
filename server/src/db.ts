import { Pool } from "pg";

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

export const query = async (sql: string, params?: any[]) => {
  const result = await pool.query(sql, params);
  return result;
};

