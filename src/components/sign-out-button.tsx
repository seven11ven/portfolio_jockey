"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { authClient } from "@/lib/auth-client";

/**
 * Signs out, then returns to the login page.
 * If the server refuses the sign-out, it stays put and says so, instead of
 * pretending it worked. (Going to /login while still signed in would just
 * bounce back here.)
 */
export function SignOutButton() {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState(false);

  async function signOut() {
    setPending(true);
    setFailed(false);
    const { error } = await authClient.signOut();
    if (error) {
      setPending(false);
      setFailed(true);
      return;
    }
    router.replace("/login");
    router.refresh();
  }

  return (
    <div className="flex flex-col items-start gap-2">
      <button
        type="button"
        onClick={signOut}
        disabled={pending}
        className="rounded-lg border border-border bg-surface px-3.5 py-2 font-semibold disabled:opacity-60"
      >
        {pending ? "Signing out…" : "Sign out"}
      </button>
      {failed && (
        <p role="alert" className="text-sm text-danger">
          Sign-out didn&apos;t work. Please try again.
        </p>
      )}
    </div>
  );
}
