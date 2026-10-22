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

  // File storage: any S3-compatible service. The project uses Backblaze B2.
  // Endpoint example: https://s3.us-west-004.backblazeb2.com
  STORAGE_ENDPOINT: z.url("must be the full S3 endpoint URL, such as https://s3.us-west-004.backblazeb2.com"),
  // Region example: us-west-004 (the part between "s3." and ".backblazeb2.com").
  STORAGE_REGION: required.regex(/^[a-z0-9-]+$/, "must be a region like us-west-004"),
  STORAGE_ACCESS_KEY_ID: required,
  STORAGE_SECRET_ACCESS_KEY: required,
  STORAGE_BUCKET: required.regex(/^[A-Za-z0-9-]{6,63}$/, "must be 6-63 letters, numbers or hyphens"),

  // 9 GB by default, below Backblaze B2's 10 GB free tier.
  STORAGE_QUOTA_BYTES: z.coerce.number().int().positive().default(9 * 1024 ** 3),
});

export type Env = z.infer<typeof envSchema>;

let cached: Env | undefined;

/** Returns the validated environment, checking it on first use. */
export function env(): Env {
  if (cached) return cached;

  // Treat "VAR=" (empty) as unset, so optional values and defaults apply.
  const raw = Object.fromEntries(
    Object.entries(process.env).filter(([, value]) => value !== ""),
  );

  const result = envSchema.safeParse(raw);
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
