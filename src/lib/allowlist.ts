import "server-only";
import { env } from "@/lib/env";

/**
 * True when the email is on the ALLOWED_EMAILS list.
 * Only these accounts can sign in. Matching ignores upper/lower case.
 */
export function isAllowedEmail(email: string | null | undefined): boolean {
  if (!email) return false;
  return env().ALLOWED_EMAILS.includes(email.trim().toLowerCase());
}
