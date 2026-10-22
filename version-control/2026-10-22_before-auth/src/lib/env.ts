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
  // The variables below are used in later steps (login and file storage).
  // They're optional for now so the database can be set up on its own.
  BETTER_AUTH_SECRET: z.string().optional(),
  BETTER_AUTH_URL: z.string().optional(),
  GITHUB_CLIENT_ID: z.string().optional(),
  GITHUB_CLIENT_SECRET: z.string().optional(),
  ALLOWED_EMAILS: z.string().optional(),
  R2_ACCOUNT_ID: z.string().optional(),
  R2_ACCESS_KEY_ID: z.string().optional(),
  R2_SECRET_ACCESS_KEY: z.string().optional(),
  R2_BUCKET: z.string().optional(),
  // 9 GB by default, below Cloudflare R2's 10 GB free tier.
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
