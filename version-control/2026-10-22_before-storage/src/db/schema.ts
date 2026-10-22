/**
 * Database schema for Portfolio Jockey.
 *
 * Tables are defined in TypeScript with Drizzle ORM. `npm run db:generate`
 * turns this file into SQL migration files in /drizzle, and
 * `npm run db:migrate` applies them to the Neon database.
 *
 * Property names here are camelCase. The database columns become
 * snake_case automatically (for example `lastOpenedAt` -> `last_opened_at`),
 * because `casing: "snake_case"` is set in drizzle.config.ts and src/db/index.ts.
 */
import {
  bigint,
  boolean,
  index,
  pgEnum,
  pgTable,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";

// Shared timestamp settings: stored with time zone, filled in automatically.
const createdAt = () => timestamp({ withTimezone: true }).notNull().defaultNow();
const updatedAt = () =>
  timestamp({ withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdate(() => new Date());

/* ------------------------------------------------------------------------ */
/* Login tables, required by Better Auth.                                    */
/* Field names must match what Better Auth expects, so don't rename them.    */
/* Better Auth creates the ids itself, which is why they're plain text.      */
/* ------------------------------------------------------------------------ */

export const user = pgTable("user", {
  id: text().primaryKey(),
  name: text().notNull(),
  email: text().notNull().unique(),
  emailVerified: boolean().notNull().default(false),
  image: text(),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

export const session = pgTable(
  "session",
  {
    id: text().primaryKey(),
    expiresAt: timestamp({ withTimezone: true }).notNull(),
    token: text().notNull().unique(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    ipAddress: text(),
    userAgent: text(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
  },
  (t) => [index("session_user_id_idx").on(t.userId)],
);

export const account = pgTable(
  "account",
  {
    id: text().primaryKey(),
    accountId: text().notNull(),
    providerId: text().notNull(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    accessToken: text(),
    refreshToken: text(),
    idToken: text(),
    accessTokenExpiresAt: timestamp({ withTimezone: true }),
    refreshTokenExpiresAt: timestamp({ withTimezone: true }),
    scope: text(),
    password: text(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index("account_user_id_idx").on(t.userId)],
);

export const verification = pgTable(
  "verification",
  {
    id: text().primaryKey(),
    identifier: text().notNull(),
    value: text().notNull(),
    expiresAt: timestamp({ withTimezone: true }).notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index("verification_identifier_idx").on(t.identifier)],
);

/* ------------------------------------------------------------------------ */
/* App tables.                                                               */
/* Every row stores its owner's userId, and every query filters by it, so    */
/* one account can never see another account's data.                         */
/* Deleting a user, project or entry cascades to the rows that belong to it. */
/* ------------------------------------------------------------------------ */

/** A portfolio project. The dashboard lists these, newest lastOpenedAt first. */
export const projects = pgTable(
  "projects",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    title: text().notNull(),
    description: text().notNull().default(""),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    // Updated every time the project page is opened. Drives dashboard order.
    lastOpenedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("projects_user_last_opened_idx").on(t.userId, t.lastOpenedAt.desc())],
);

/**
 * One item on a project's timeline: a text note, uploaded files, or both.
 * The body doubles as a caption when files are attached.
 */
export const entries = pgTable(
  "entries",
  {
    id: uuid().primaryKey().defaultRandom(),
    projectId: uuid()
      .notNull()
      .references(() => projects.id, { onDelete: "cascade" }),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    body: text().notNull().default(""),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index("entries_project_created_idx").on(t.projectId, t.createdAt.desc())],
);

/**
 * Upload status:
 * - pending: an upload link was issued, but the browser hasn't confirmed it finished.
 * - ready:   the file is in R2 and shows on the timeline.
 * Pending files still count toward the storage quota, so starting many
 * uploads at once can't sneak past the free-tier limit.
 */
export const fileStatus = pgEnum("file_status", ["pending", "ready"]);

/**
 * Metadata for a file stored in the private Cloudflare R2 bucket.
 * The file itself lives in R2, never in the database or the repo.
 */
export const files = pgTable(
  "files",
  {
    id: uuid().primaryKey().defaultRandom(),
    entryId: uuid()
      .notNull()
      .references(() => entries.id, { onDelete: "cascade" }),
    // Stored directly as well, so deleting or exporting a project can find
    // all its files in one query.
    projectId: uuid()
      .notNull()
      .references(() => projects.id, { onDelete: "cascade" }),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    // Random object key in R2, shaped like userId/projectId/uuid.
    // The original file name is never used as the key.
    r2Key: text().notNull().unique(),
    originalName: text().notNull(),
    mimeType: text().notNull(),
    sizeBytes: bigint({ mode: "number" }).notNull(),
    status: fileStatus().notNull().default("pending"),
    createdAt: createdAt(),
  },
  (t) => [
    index("files_entry_idx").on(t.entryId),
    index("files_project_idx").on(t.projectId),
    index("files_user_idx").on(t.userId),
  ],
);
