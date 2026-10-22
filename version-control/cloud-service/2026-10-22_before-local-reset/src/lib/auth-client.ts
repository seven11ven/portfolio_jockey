"use client";
import { createAuthClient } from "better-auth/react";

/**
 * Browser-side login helpers (sign in, sign out).
 * It talks to /api/auth on the same site, so no address is needed.
 * This file contains no secrets.
 */
export const authClient = createAuthClient();
