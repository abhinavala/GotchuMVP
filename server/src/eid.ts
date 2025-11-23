import { randomBytes } from "crypto"; // Import crypto module for random bytes

export const newEID = (): string => { // Function to generate new EID
  return randomBytes(5).toString("hex"); // Generate 5 random bytes and convert to hex (10 chars)
}; // End newEID
