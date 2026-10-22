import { toNextJsHandler } from "better-auth/next-js";
import { auth } from "@/lib/auth";

/**
 * Handles every request to /api/auth/*, such as starting GitHub sign-in,
 * the GitHub callback, and signing out. Better Auth does the work.
 */
export const { GET, POST } = toNextJsHandler(auth);
