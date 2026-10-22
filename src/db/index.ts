import "server-only";
import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";
import { env } from "@/lib/env";
import * as schema from "./schema";

/**
 * The database client used across the app.
 *
 * It uses Neon's HTTP driver, which sends each query as a single HTTPS
 * request. That suits Vercel's serverless functions, because no long-lived
 * connection has to be opened or closed.
 *
 * `server-only` makes the build fail if browser code imports this file.
 */
export const db = drizzle({
  client: neon(env().DATABASE_URL),
  schema,
  casing: "snake_case",
});

export { schema };
