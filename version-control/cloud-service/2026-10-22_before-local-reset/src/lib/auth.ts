import "server-only";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { nextCookies } from "better-auth/next-js";
import { db, schema } from "@/db";
import { isAllowedEmail } from "@/lib/allowlist";
import { env } from "@/lib/env";

/**
 * Login setup, using Better Auth with GitHub as the only sign-in method.
 *
 * Security choices:
 * - No passwords. GitHub proves who you are, so the app never stores one.
 * - An allowlist. Only emails in ALLOWED_EMAILS get in, so strangers who
 *   find the site can't create accounts.
 * - GitHub tokens are encrypted before they're saved in the database.
 */
export const auth = betterAuth({
  baseURL: env().BETTER_AUTH_URL,
  secret: env().BETTER_AUTH_SECRET,

  // Requests that carry a login cookie must come from a trusted address.
  // BETTER_AUTH_URL is always trusted. TRUSTED_ORIGINS adds extra ones,
  // which GitHub Codespaces needs because its proxy rewrites the Origin
  // header to https://localhost:3000. See .env_example.
  trustedOrigins: env().TRUSTED_ORIGINS,

  database: drizzleAdapter(db, {
    provider: "pg",
    schema,
    // Neon's HTTP driver doesn't support multi-step transactions.
    // Better Auth only needs them on MySQL, so this is safe on Postgres.
    transaction: false,
  }),

  socialProviders: {
    github: {
      clientId: env().GITHUB_CLIENT_ID,
      clientSecret: env().GITHUB_CLIENT_SECRET,
      // Default scopes only: read the public profile and email addresses.
      // No access to repositories or anything else.
    },
  },

  user: {
    /**
     * Runs on every new account, account link, and GitHub sign-in.
     * On sign-in it receives the fresh email from GitHub, so changing
     * your GitHub email to one that isn't allowed also locks you out.
     */
    validateUserInfo: async ({ user }) => {
      if (!user.emailVerified || !isAllowedEmail(user.email)) {
        return {
          error: "not_allowed",
          errorDescription: "This GitHub account isn't approved to use this app.",
        };
      }
    },
  },

  account: {
    encryptOAuthTokens: true,
  },

  // Login errors send people back to the login page, which shows a message.
  onAPIError: {
    errorURL: "/login",
  },

  // Lets server actions set and clear login cookies. Must be the last plugin.
  plugins: [nextCookies()],
});
