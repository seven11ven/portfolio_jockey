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
  integer,
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
 * - ready:   the file is in the store and shows on the timeline.
 * Pending files still count toward the storage quota, so starting many
 * uploads at once can't sneak past the free-tier limit.
 */
export const fileStatus = pgEnum("file_status", ["pending", "ready"]);

/**
 * Metadata for a file stored in the private Vercel Blob store.
 * The file itself lives in the store, never in the database or the repo.
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
    // The file's pathname in the Blob store: userId/projectId/uuid/name.
    // The random uuid folder keeps it unguessable and unique. The name is a
    // cleaned, URL-safe copy of the original, so downloads get a sensible name.
    storageKey: text().notNull().unique(),
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

/**
 * Files that were deleted in the app but are still kept in storage for a while.
 *
 * Deleting an entry or project removes its rows from `files` right away and
 * records each stored file here. The file itself is only removed from the
 * Blob store after the retention period (7 days), so a mistake can still be
 * recovered from the Vercel dashboard. Until then it still counts toward
 * the storage quota, because the store still holds it.
 *
 * There's deliberately no foreign key to `user`: if a user is deleted,
 * these rows must survive so their objects still get cleaned up.
 */
export const deletedObjects = pgTable(
  "deleted_objects",
  {
    storageKey: text().primaryKey(),
    userId: text().notNull(),
    // Kept so the owner can find a file in the Vercel dashboard to recover it.
    originalName: text().notNull(),
    mimeType: text().notNull(),
    sizeBytes: bigint({ mode: "number" }).notNull(),
    deletedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index("deleted_objects_user_idx").on(t.userId),
    index("deleted_objects_deleted_at_idx").on(t.deletedAt),
  ],
);

/**
 * The app's own record of estimated Vercel Blob usage, used to stay inside
 * the free Hobby allowance. See src/lib/blob-usage.ts.
 * Not tied to a user, because Vercel's limits apply to the whole account.
 */
export const blobUsageEvents = pgTable(
  "blob_usage_events",
  {
    id: uuid().primaryKey().defaultRandom(),
    at: timestamp({ withTimezone: true }).notNull().defaultNow(),
    advancedOps: integer().notNull().default(0),
    simpleOps: integer().notNull().default(0),
    transferBytes: bigint({ mode: "number" }).notNull().default(0),
  },
  (t) => [index("blob_usage_events_at_idx").on(t.at)],
);
