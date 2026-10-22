import "server-only";
import { cache } from "react";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { auth } from "@/lib/auth";
import { isAllowedEmail } from "@/lib/allowlist";

export type CurrentUser = {
  id: string;
  name: string;
  email: string;
  image: string | null;
};

/**
 * Returns the signed-in user, or null.
 *
 * This is the real security check. The proxy (src/proxy.ts) only does a
 * quick cookie check to redirect early. Every page and server action that
 * touches private data must call requireUser() itself.
 *
 * The allowlist is checked again on every request, so removing an email
 * from ALLOWED_EMAILS locks that account out right away, even if it still
 * has a valid session.
 *
 * `cache` means the lookup runs at most once per request.
 *
 * With Next.js 16 Cache Components, anything that calls this reads the
 * request, so it must render inside a <Suspense> boundary.
 */
export const getCurrentUser = cache(async (): Promise<CurrentUser | null> => {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session || !isAllowedEmail(session.user.email)) return null;
  // Return only the fields the app needs, never the raw session or tokens.
  const { id, name, email, image } = session.user;
  return { id, name, email, image: image ?? null };
});

/** Returns the signed-in user, or sends the visitor to /login. */
export async function requireUser() {
  const user = await getCurrentUser();
  if (!user) redirect("/login");
  return user;
}
