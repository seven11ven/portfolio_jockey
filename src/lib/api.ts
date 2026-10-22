import "server-only";
import { NextResponse } from "next/server";
import { env } from "@/lib/env";
import { getCurrentUser } from "@/lib/session";

/**
 * Helpers shared by the app's own API routes (not the login routes,
 * which Better Auth protects itself).
 */

/** A JSON error response that never caches. */
export function apiError(status: number, code: string, message: string) {
  return NextResponse.json({ error: code, message }, { status, headers: { "Cache-Control": "no-store" } });
}

/**
 * Blocks cross-site request forgery: a request that changes data must
 * come from the app's own address (or a TRUSTED_ORIGINS entry). Browsers
 * always send the Origin header on POST requests, and other websites
 * can't fake it.
 */
export function isTrustedOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin) return false;
  const trusted = [new URL(env().BETTER_AUTH_URL).origin, ...env().TRUSTED_ORIGINS];
  return trusted.includes(origin);
}

/**
 * Returns the signed-in user, or an error response to send back.
 * Pass `checkOrigin: true` for any request that changes data.
 */
export async function authorize(request: Request, { checkOrigin }: { checkOrigin: boolean }) {
  if (checkOrigin && !isTrustedOrigin(request)) {
    return { user: null, response: apiError(403, "bad_origin", "Request blocked.") } as const;
  }
  const user = await getCurrentUser();
  if (!user) {
    return { user: null, response: apiError(401, "not_signed_in", "Please sign in.") } as const;
  }
  return { user, response: null } as const;
}
