import jwt from "jsonwebtoken"; // Import JWT library for token signing/verification
import { Request, Response, NextFunction } from "express"; // Import Express types

export function signDev(uid: string): string { // Function to sign JWT token for dev login
  if (!process.env.JWT_SECRET) { // Check if JWT secret is set
    throw new Error("JWT_SECRET not set"); // Throw error if missing
  } // End if
  return jwt.sign({ uid }, process.env.JWT_SECRET, { expiresIn: "7d" }); // Sign token with 7 day expiration
} // End signDev

export function requireAuth(req: Request, res: Response, next: NextFunction) { // Middleware to require authentication
  const token = (req.headers.authorization || "").replace(/^Bearer /, ""); // Extract token from Authorization header
  if (!token) { // Check if token exists
    return res.status(401).json({ error: "unauthorized" }); // Return 401 if no token
  } // End if
  if (!process.env.JWT_SECRET) { // Check if JWT secret is set
    return res.status(500).json({ error: "server configuration error" }); // Return 500 if missing
  } // End if
  try { // Begin try block
    const payload = jwt.verify(token, process.env.JWT_SECRET) as any; // Verify and decode token
    (req as any).userId = payload.uid; // Attach user ID to request object
    next(); // Call next middleware
  } catch { // Catch invalid token errors
    res.status(401).json({ error: "unauthorized" }); // Return 401 if token invalid
  } // End catch
} // End requireAuth
