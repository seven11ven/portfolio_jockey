import { NextResponse, type NextRequest } from "next/server";
import { getSessionCookie } from "better-auth/cookies";

/**
 * Runs before every matching request (Next.js 16 calls this "proxy",
 * older versions called it "middleware").
 *
 * It only checks whether a login cookie EXISTS, and sends visitors without
 * one to /login. That's fast, but it's not a security check, because a
 * cookie can be faked. The real check is requireUser() in src/lib/session.ts.
 */
export function proxy(request: NextRequest) {
  if (!getSessionCookie(request)) {
    return NextResponse.redirect(new URL("/login", request.url));
  }
  return NextResponse.next();
}

export const config = {
  // Run on everything except the login page, the login API, Next.js
  // internal files, and static files like the favicon.
  matcher: ["/((?!login|api/auth|_next/static|_next/image|favicon.ico).*)"],
};
