import { defineConfig } from "drizzle-kit";

/**
 * Config for drizzle-kit, the command-line tool that creates and applies
 * database migrations. Next.js loads .env by itself, but drizzle-kit
 * doesn't, so it's loaded here with Node's built-in loader.
 */
try {
  process.loadEnvFile(".env");
} catch {
  // No .env file. Fine for `db:generate`, which doesn't connect to the database.
}

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  casing: "snake_case",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "",
  },
  strict: true,
  verbose: true,
});
