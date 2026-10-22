"use client";
import { useState } from "react";
import { authClient } from "@/lib/auth-client";

/** The "Continue with GitHub" button. Sends the browser to GitHub to sign in. */
export function GitHubSignInButton() {
  const [pending, setPending] = useState(false);

  async function signIn() {
    setPending(true);
    await authClient.signIn.social({ provider: "github", callbackURL: "/" });
    // On success the browser leaves this page, so there's nothing more to do.
    // If the request itself fails, re-enable the button so it can be retried.
    setPending(false);
  }

  return (
    <button
      type="button"
      onClick={signIn}
      disabled={pending}
      className="flex items-center justify-center gap-2 rounded-lg border border-[#24292f] bg-[#24292f] p-3 font-semibold text-white disabled:opacity-60"
    >
      <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38v-1.33c-2.23.48-2.7-1.07-2.7-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.06-.49.06-.49.8.06 1.23.83 1.23.83.72 1.22 1.88.87 2.34.66.07-.52.28-.87.5-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
      </svg>
      {pending ? "Redirecting to GitHub…" : "Continue with GitHub"}
    </button>
  );
}
