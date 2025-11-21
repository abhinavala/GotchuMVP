import jwt from "jsonwebtoken";
import { Request, Response, NextFunction } from "express";

export function signDev(uid: string): string {
  if (!process.env.JWT_SECRET) {
    throw new Error("JWT_SECRET not set");
  }
  return jwt.sign({ uid }, process.env.JWT_SECRET, { expiresIn: "7d" });
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const token = (req.headers.authorization || "").replace(/^Bearer /, "");
  if (!token) {
    return res.status(401).json({ error: "unauthorized" });
  }
  if (!process.env.JWT_SECRET) {
    return res.status(500).json({ error: "server configuration error" });
  }
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET) as any;
    (req as any).userId = payload.uid;
    next();
  } catch {
    res.status(401).json({ error: "unauthorized" });
  }
}

