import "server-only";
import { randomUUID } from "node:crypto";
import { and, eq, inArray, sql } from "drizzle-orm";
import { db } from "@/db";
import { deletedObjects, entries, files } from "@/db/schema";
import { pruneBlobUsage, reserveBlobUsage } from "@/lib/blob-usage";
import { env } from "@/lib/env";
import { cleanFileName, isAllowedMimeType, MAX_FILE_BYTES } from "@/lib/file-types";
import {
  createViewUrl,
  deleteObjects,
  getObjectInfo,
  issueUploadPermission,
  MULTIPART_PART_BYTES,
  MULTIPART_THRESHOLD_BYTES,
  readTokenNeedsRenewal,
} from "@/lib/object-storage";

/**
 * File storage rules: uploads, downloads, deletes, the storage quota, and
 * the Vercel Blob free-allowance guard.
 *
 * Every function takes the signed-in user's id and only touches that
 * user's rows, so one account can never reach another account's files.
 * Callers must get userId from the session (src/lib/session.ts), never
 * from the request body.
 */

/** Deleted files stay in the store this long before they're removed for good. */
export const RETENTION_DAYS = 7;
/** Uploads never confirmed after this long are treated as abandoned. */
const ABANDONED_UPLOAD_HOURS = 24;
/** An upload must start within this long of being approved. */
const UPLOAD_WINDOW_MINUTES = 15;

/** Ids are UUIDs. Checking first means a malformed id is a clean "not found". */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (value: string) => UUID.test(value);

export type StorageError = {
  ok: false;
  status: 400 | 404 | 409 | 413 | 429;
  code: string;
  message: string;
};
const fail = (status: StorageError["status"], code: string, message: string): StorageError => ({
  ok: false,
  status,
  code,
  message,
});
const ALLOWANCE_USED_UP = () =>
  fail(
    429,
    "free_allowance_used",
    "This month's free file storage allowance is almost used up. Try again in a few days.",
  );

/** Whether a file of this size is uploaded in parts. */
export const usesMultipart = (sizeBytes: number) => sizeBytes > MULTIPART_THRESHOLD_BYTES;

/** Vercel Blob operations an upload of this size uses: one per part, plus start and finish. */
function uploadOperations(sizeBytes: number) {
  return usesMultipart(sizeBytes) ? Math.ceil(sizeBytes / MULTIPART_PART_BYTES) + 2 : 1;
}

/**
 * Makes the last part of a pathname from the original file name: only
 * letters, numbers, dots, dashes and underscores, never starting with a dot.
 */
function pathnameSafeName(fileName: string) {
  const safe = fileName
    .replace(/[^A-Za-z0-9._-]+/g, "_")
    .replace(/^[._]+/, "")
    .slice(0, 100);
  return safe || "file";
}

/* ------------------------------------------------------------------ */
/* Quota                                                               */
/* ------------------------------------------------------------------ */

/**
 * Bytes this user is using. It counts live files, pending uploads, and
 * deleted files still waiting out the retention period, because the
 * store holds all of them.
 */
export async function getStorageUsage(userId: string) {
  const result = await db.execute<{ used: string }>(sql`
    select
      (select coalesce(sum(size_bytes), 0) from files where user_id = ${userId})
      + (select coalesce(sum(size_bytes), 0) from deleted_objects where user_id = ${userId})
      as used
  `);
  return { usedBytes: Number(result.rows[0]?.used ?? 0), quotaBytes: env().STORAGE_QUOTA_BYTES };
}

/* ------------------------------------------------------------------ */
/* Uploads                                                             */
/* ------------------------------------------------------------------ */

export type UploadRequest = {
  entryId: string;
  fileName: string;
  contentType: string;
  sizeBytes: number;
};

/**
 * Step 1 of an upload: checks the rules, reserves quota and free allowance,
 * and records a "pending" file. Returns the pathname the browser must
 * upload to, and whether to upload in parts.
 */
export async function createUpload(userId: string, request: UploadRequest) {
  if (!isAllowedMimeType(request.contentType)) {
    return fail(400, "type_not_allowed", "Only images, audio, video, PDF and text files are allowed.");
  }
  if (!Number.isInteger(request.sizeBytes) || request.sizeBytes <= 0) {
    return fail(400, "invalid_size", "The file is empty or its size is invalid.");
  }
  if (request.sizeBytes > MAX_FILE_BYTES) {
    return fail(413, "file_too_large", "Files can be up to 500 MB each.");
  }

  // The entry must exist and belong to this user.
  if (!isUuid(request.entryId)) return fail(404, "entry_not_found", "That entry doesn't exist.");
  const [entry] = await db
    .select({ projectId: entries.projectId })
    .from(entries)
    .where(and(eq(entries.id, request.entryId), eq(entries.userId, userId)))
    .limit(1);
  if (!entry) return fail(404, "entry_not_found", "That entry doesn't exist.");

  const fileName = cleanFileName(request.fileName);
  const pathname = `${userId}/${entry.projectId}/${randomUUID()}/${pathnameSafeName(fileName)}`;
  const quota = env().STORAGE_QUOTA_BYTES;

  // Checking the quota and reserving the space happen in one transaction,
  // behind a lock that's unique to this user, so two uploads started at the
  // same moment can't both squeeze past the limit.
  const [, inserted] = await db.batch([
    db.execute(sql`select pg_advisory_xact_lock(hashtext(${"quota:" + userId}))`),
    db.execute<{ id: string }>(sql`
      insert into files (entry_id, project_id, user_id, storage_key, original_name, mime_type, size_bytes)
      select ${request.entryId}::uuid, ${entry.projectId}::uuid, ${userId}, ${pathname},
             ${fileName}, ${request.contentType}, ${request.sizeBytes}::bigint
      where (select coalesce(sum(size_bytes), 0) from files where user_id = ${userId})
          + (select coalesce(sum(size_bytes), 0) from deleted_objects where user_id = ${userId})
          + ${request.sizeBytes}::bigint <= ${quota}::bigint
      returning id
    `),
  ]);
  const fileId = inserted.rows[0]?.id;
  if (!fileId) return fail(413, "quota_exceeded", "This upload would go over your storage limit.");

  // Upload operations, plus one for the upload permission request.
  const allowed = await reserveBlobUsage({ advancedOps: uploadOperations(request.sizeBytes) + 1 });
  if (!allowed) {
    await db.delete(files).where(and(eq(files.id, fileId), eq(files.userId, userId)));
    return ALLOWANCE_USED_UP();
  }

  return { ok: true as const, fileId, pathname, multipart: usesMultipart(request.sizeBytes) };
}

/**
 * Step 2 of an upload: the browser asks for permission to upload one
 * approved file. Only works for this user's own pending file, at the exact
 * pathname from step 1, within 15 minutes. Throws if not allowed.
 */
export async function authorizeUpload(userId: string, fileId: string, pathname: string, multipart: boolean) {
  if (!isUuid(fileId)) throw new UploadNotAllowedError();
  const [file] = await db
    .select()
    .from(files)
    .where(
      and(
        eq(files.id, fileId),
        eq(files.userId, userId),
        eq(files.status, "pending"),
        eq(files.storageKey, pathname),
        sql`${files.createdAt} > now() - make_interval(mins => ${UPLOAD_WINDOW_MINUTES})`,
      ),
    )
    .limit(1);
  if (!file || multipart !== usesMultipart(file.sizeBytes)) throw new UploadNotAllowedError();
  return issueUploadPermission(file.storageKey, file.mimeType, file.sizeBytes);
}

export class UploadNotAllowedError extends Error {
  constructor() {
    super("Upload not allowed.");
  }
}

/**
 * Step 3 of an upload: the browser says it finished. The server checks
 * that the store really has the file, with the approved size and type,
 * before showing it. A mismatch deletes the upload.
 */
export async function completeUpload(userId: string, fileId: string) {
  if (!isUuid(fileId)) return fail(404, "file_not_found", "That file doesn't exist.");
  const [file] = await db
    .select()
    .from(files)
    .where(and(eq(files.id, fileId), eq(files.userId, userId)))
    .limit(1);
  if (!file) return fail(404, "file_not_found", "That file doesn't exist.");
  if (file.status === "ready") return { ok: true as const, fileId };

  if (!(await reserveBlobUsage({ simpleOps: 1 }))) return ALLOWANCE_USED_UP();
  const info = await getObjectInfo(file.storageKey);
  if (!info) return fail(409, "not_uploaded", "The file hasn't finished uploading.");

  if (info.sizeBytes !== file.sizeBytes || info.contentType !== file.mimeType) {
    await deleteObjects([file.storageKey]);
    await db.delete(files).where(and(eq(files.id, file.id), eq(files.userId, userId)));
    return fail(400, "upload_mismatch", "The uploaded file didn't match what was approved, so it was removed.");
  }

  await db
    .update(files)
    .set({ status: "ready" })
    .where(and(eq(files.id, file.id), eq(files.userId, userId)));
  return { ok: true as const, fileId };
}

/* ------------------------------------------------------------------ */
/* Downloads                                                           */
/* ------------------------------------------------------------------ */

/**
 * A 10-minute link to view or download a finished file.
 * Returns a StorageError if the file isn't found or the free allowance is
 * used up.
 */
export async function getDownloadUrl(userId: string, fileId: string, asAttachment: boolean) {
  if (!isUuid(fileId)) return fail(404, "file_not_found", "That file doesn't exist.");
  const [file] = await db
    .select()
    .from(files)
    .where(and(eq(files.id, fileId), eq(files.userId, userId), eq(files.status, "ready")))
    .limit(1);
  if (!file) return fail(404, "file_not_found", "That file doesn't exist.");

  // Counted as a full, uncached download (the worst case).
  const allowed = await reserveBlobUsage({
    simpleOps: 1,
    transferBytes: file.sizeBytes,
    advancedOps: readTokenNeedsRenewal() ? 1 : 0,
  });
  if (!allowed) return ALLOWANCE_USED_UP();

  return { ok: true as const, url: await createViewUrl(file.storageKey, asAttachment) };
}

/* ------------------------------------------------------------------ */
/* Deletes                                                             */
/* ------------------------------------------------------------------ */

/**
 * Deletes an entry and its files. The files move to deleted_objects and
 * stay in the store for RETENTION_DAYS. Both statements run as one
 * transaction, so a file is never lost track of halfway.
 * Returns false if the entry doesn't exist or isn't this user's.
 */
export async function deleteEntry(userId: string, entryId: string) {
  if (!isUuid(entryId)) return false;
  const [, deleted] = await db.batch([
    db.execute(sql`
      insert into deleted_objects (storage_key, user_id, original_name, mime_type, size_bytes)
      select f.storage_key, f.user_id, f.original_name, f.mime_type, f.size_bytes
      from files f
      join entries e on e.id = f.entry_id
      where e.id = ${entryId}::uuid and e.user_id = ${userId}
      on conflict (storage_key) do nothing
    `),
    db
      .delete(entries)
      .where(and(eq(entries.id, entryId), eq(entries.userId, userId)))
      .returning({ id: entries.id }),
  ]);
  return deleted.length > 0;
}

/** Deletes a project with all its entries and files. Same rules as deleteEntry. */
export async function deleteProject(userId: string, projectId: string) {
  if (!isUuid(projectId)) return false;
  const [, deleted] = await db.batch([
    db.execute(sql`
      insert into deleted_objects (storage_key, user_id, original_name, mime_type, size_bytes)
      select f.storage_key, f.user_id, f.original_name, f.mime_type, f.size_bytes
      from files f
      join projects p on p.id = f.project_id
      where p.id = ${projectId}::uuid and p.user_id = ${userId}
      on conflict (storage_key) do nothing
    `),
    db.execute<{ id: string }>(sql`
      delete from projects where id = ${projectId}::uuid and user_id = ${userId} returning id
    `),
  ]);
  return deleted.rows.length > 0;
}

/* ------------------------------------------------------------------ */
/* Cleanup                                                             */
/* ------------------------------------------------------------------ */

/**
 * Housekeeping, run in the background after uploads:
 * 1. Uploads never confirmed within a day are abandoned. They're queued
 *    for immediate removal, since there's nothing worth recovering.
 * 2. Deleted files older than the retention period are removed from the
 *    store for good. Deleting is free on Vercel Blob.
 * 3. Old allowance records are pruned.
 */
export async function cleanUpStorage() {
  await db.batch([
    db.execute(sql`
      insert into deleted_objects (storage_key, user_id, original_name, mime_type, size_bytes, deleted_at)
      select storage_key, user_id, original_name, mime_type, size_bytes,
             now() - make_interval(days => ${RETENTION_DAYS})
      from files
      where status = 'pending'
        and created_at < now() - make_interval(hours => ${ABANDONED_UPLOAD_HOURS})
      on conflict (storage_key) do nothing
    `),
    db.execute(sql`
      delete from files
      where status = 'pending'
        and created_at < now() - make_interval(hours => ${ABANDONED_UPLOAD_HOURS})
    `),
  ]);

  const expired = await db.execute<{ storage_key: string }>(sql`
    select storage_key from deleted_objects
    where deleted_at <= now() - make_interval(days => ${RETENTION_DAYS})
    order by deleted_at
    limit 1000
  `);
  const removed = await deleteObjects(expired.rows.map((row) => row.storage_key));
  if (removed.length > 0) {
    await db.delete(deletedObjects).where(inArray(deletedObjects.storageKey, removed));
  }
  await pruneBlobUsage();
  return { removed: removed.length };
}
