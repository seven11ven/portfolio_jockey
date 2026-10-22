import { Suspense } from "react";
import { SignOutButton } from "@/components/sign-out-button";
import { requireUser } from "@/lib/session";

/**
 * TEMPORARY page for testing login (plan step 4).
 * It's replaced by the real dashboard in plan step 6, built to the
 * approved mockup in project-mockups/dashboard.html.
 */
export default function HomePage() {
  return (
    <main className="mx-auto flex w-full max-w-[520px] flex-col gap-4 p-6">
      <h1 className="text-2xl font-bold">Signed in</h1>
      <Suspense fallback={<p className="text-muted">Checking your session…</p>}>
        <SignedInDetails />
      </Suspense>
    </main>
  );
}

async function SignedInDetails() {
  const user = await requireUser();
  return (
    <>
      <p className="text-muted">
        You&apos;re signed in as <strong className="text-text">{user.name}</strong> ({user.email}).
        The dashboard comes in a later step.
      </p>
      <div>
        <SignOutButton />
      </div>
    </>
  );
}
