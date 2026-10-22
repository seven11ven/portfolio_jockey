import { Suspense } from "react";
import { redirect } from "next/navigation";
import { GitHubSignInButton } from "@/components/github-sign-in-button";
import { getCurrentUser } from "@/lib/session";

// Friendly messages for known login errors. Unknown codes get a generic
// message, so nothing from the URL is ever shown on the page as-is.
const ERROR_MESSAGES: Record<string, string> = {
  not_allowed: "This GitHub account isn't approved to use this app.",
  access_denied: "GitHub sign-in was cancelled.",
};
const GENERIC_ERROR = "Sign-in didn't work. Please try again.";

/**
 * The card is static, so it loads instantly. The parts that read the
 * request (the "already signed in?" check and the error message from the
 * URL) stream in behind a <Suspense> boundary, as Next.js 16 requires.
 */
export default function LoginPage({ searchParams }: PageProps<"/login">) {
  return (
    <main className="grid flex-1 place-items-center p-4">
      <div className="flex w-full max-w-[380px] flex-col gap-4 rounded-xl border border-border bg-surface p-7 text-center shadow-sm">
        <div className="flex items-center justify-center gap-2 font-bold">
          <span className="grid size-7 place-items-center rounded-lg bg-accent text-sm text-white">PJ</span>
          <span>Portfolio Jockey</span>
        </div>
        <div>
          <h1 className="text-[22px] font-bold leading-tight">Welcome back</h1>
          <p className="mt-1.5 text-muted">Sign in to see your portfolio.</p>
        </div>
        <Suspense fallback={null}>
          <LoginStatus searchParams={searchParams} />
        </Suspense>
        <GitHubSignInButton />
        <p className="text-[13px] text-muted">Access is limited to approved accounts.</p>
      </div>
    </main>
  );
}

async function LoginStatus({ searchParams }: Pick<PageProps<"/login">, "searchParams">) {
  // Already signed in? Skip the login page.
  if (await getCurrentUser()) redirect("/");

  const { error } = await searchParams;
  const code = typeof error === "string" ? error : undefined;
  if (!code) return null;

  return (
    <p role="alert" className="rounded-lg bg-danger-soft px-3 py-2.5 text-sm text-danger">
      {ERROR_MESSAGES[code] ?? GENERIC_ERROR}
    </p>
  );
}
