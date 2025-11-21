import { randomBytes } from "crypto";

export const newEID = (): string => {
  return randomBytes(5).toString("hex"); // 10 chars
};

