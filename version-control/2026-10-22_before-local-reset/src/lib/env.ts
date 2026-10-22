import "server-only";
import { z } from "zod";

/**
 * Server-side environment variables, checked once with zod.
 *
 * Why: if a variable is missing or malformed, the app fails fast with a
 * clear message naming the variable, instead of a confusing error later.
 * Error messages name the variable but NEVER print its value, because
 * values are secrets and this repo is public.
 *
 * Each variable is documented in /.env_example.
 * The `server-only` import makes the build fail if a browser component
 * ever imports this file, so secrets can't leak into client code.
 */

// Empty strings count as "not set", so a blank line in .env is caught too.
const required = z.string().trim().min(1, "is required");

const envSchema = z.object({
  DATABASE_URL: required.startsWith("postgres", "must be a Postgres connection string"),

  // Login (Better Auth + GitHub)
  BETTER_AUTH_SECRET: required.min(32, "must be at least 32 characters (see .env_example for a command that generates one)"),
  BETTER_AUTH_URL: z.url("must be a full URL, such as http://localhost:3000"),
  GITHUB_CLIENT_ID: required,
  GITHUB_CLIENT_SECRET: required,
  // Comma-separated emails. Turned into a lowercase list, so matching ignores case.
  ALLOWED_EMAILS: required.transform((value) =>
    value
      .split(",")
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  ),

  // Extra addresses allowed to make logged-in requests, besides BETTER_AUTH_URL.
  // Only needed behind a proxy that rewrites the Origin header, such as
  // GitHub Codespaces port forwarding. Leave empty on Vercel.
  // Comma-separated full origins, such as https://localhost:3000
  TRUSTED_ORIGINS: z
    .string()
    .optional()
    .transform((value) =>
      (value ?? "")
        .split(",")
        .map((origin) => origin.trim())
        .filter(Boolean),
    )
    .pipe(
      z.array(
        z.url("each entry must be a full origin, such as https://localhost:3000").refine(
          (origin) => new URL(origin).origin === origin,
          "each entry must be just scheme, host and port, with no path or trailing slash",
        ),
      ),
    ),

  // File storage: a PRIVATE Vercel Blob store. The Blob SDK reads these itself.
  // Locally, set BLOB_READ_WRITE_TOKEN. On Vercel, connecting the store to the
  // project adds BLOB_STORE_ID (and a short-lived OIDC token) automatically.
  BLOB_READ_WRITE_TOKEN: z.string().optional(),
  BLOB_STORE_ID: z.string().optional(),

  // 900 MB by default, below Vercel Blob's 1 GB Hobby allowance.
  STORAGE_QUOTA_BYTES: z.coerce.number().int().positive().default(900_000_000),
});

export type Env = z.infer<typeof envSchema>;

// The Blob SDK needs one of these two to reach the store.
const blobCredentialsCheck = (value: Env) =>
  Boolean(value.BLOB_READ_WRITE_TOKEN || value.BLOB_STORE_ID);

let cached: Env | undefined;

/** Returns the validated environment, checking it on first use. */
export function env(): Env {
  if (cached) return cached;

  // Treat "VAR=" (empty) as unset, so optional values and defaults apply.
  const raw = Object.fromEntries(
    Object.entries(process.env).filter(([, value]) => value !== ""),
  );

  const result = envSchema
    .refine(blobCredentialsCheck, {
      path: ["BLOB_READ_WRITE_TOKEN"],
      message: "is required (or BLOB_STORE_ID when running on Vercel)",
    })
    .safeParse(raw);
  if (!result.success) {
    const problems = result.error.issues
      .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
      .join("\n");
    throw new Error(
      `Invalid environment variables:\n${problems}\n` +
        "See /.env_example for what each one does and how to set it up.",
    );
  }

  cached = result.data;
  return cached;
}
