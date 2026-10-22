import "server-only";
import { randomUUID } from "node:crypto";
import { and, eq, inArray, sql } from "drizzle-orm";
import { db } from "@/db";
import { deletedObjects, entries, files } from "@/db/schema";
import { env } from "@/lib/env";
import { cleanFileName, isAllowedMimeType, MAX_FILE_BYTES } from "@/lib/file-types";
import { createDownloadUrl, createUploadUrl, deleteObjects, getObjectInfo } from "@/lib/object-storage";

/**
 * File storage rules: uploads, downloads, deletes and the storage quota.
 *
 * Every function takes the signed-in user's id and only touches that
 * user's rows, so one account can never reach another account's files.
 * Callers must get userId from the session (src/lib/session.ts), never
 * from the request body.
 */

/** Deleted files stay in the bucket this long before they're removed for good. */
export const RETENTION_DAYS = 7;
/** Uploads never confirmed after this long are treated as abandoned. */
const ABANDONED_UPLOAD_HOURS = 24;

export type StorageError = {
  ok: false;
  status: 400 | 404 | 409 | 413;
  code: string;
  message: string;
};
/** Ids are UUIDs. Checking first means a malformed id is a clean "not found". */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (value: string) => UUID.test(value);

const fail = (status: StorageError["status"], code: string, message: string): StorageError => ({
  ok: false,
  status,
  code,
  message,
});

/* ------------------------------------------------------------------ */
/* Quota                                                               */
/* ------------------------------------------------------------------ */

/**
 * Bytes this user is using. It counts live files, pending uploads, and
 * deleted files still waiting out the retention period, because the bucket
 * stores all of them.
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
 * Step 1 of an upload: checks the rules, reserves quota, and returns a
 * short-lived link the browser uploads the file to directly.
 * The file row starts as "pending" and counts toward the quota at once,
 * so many uploads started together can't slip past the limit.
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

  // Random key. The original file name is never part of it.
  const key = `${userId}/${entry.projectId}/${randomUUID()}`;
  const fileName = cleanFileName(request.fileName);
  const quota = env().STORAGE_QUOTA_BYTES;

  // Checking the quota and reserving the space happen in one transaction,
  // behind a lock that's unique to this user. A second upload started at
  // the same moment waits for the first to finish, then sees its size, so
  // two uploads can't both squeeze past the limit.
  const [, inserted] = await db.batch([
    db.execute(sql`select pg_advisory_xact_lock(hashtext(${"quota:" + userId}))`),
    db.execute<{ id: string }>(sql`
    insert into files (entry_id, project_id, user_id, storage_key, original_name, mime_type, size_bytes)
    select ${request.entryId}::uuid, ${entry.projectId}::uuid, ${userId}, ${key},
           ${fileName}, ${request.contentType}, ${request.sizeBytes}::bigint
    where (select coalesce(sum(size_bytes), 0) from files where user_id = ${userId})
        + (select coalesce(sum(size_bytes), 0) from deleted_objects where user_id = ${userId})
        + ${request.sizeBytes}::bigint <= ${quota}::bigint
    returning id
  `),
  ]);
  const fileId = inserted.rows[0]?.id;
  if (!fileId) {
    return fail(413, "quota_exceeded", "This upload would go over your storage limit.");
  }

  const uploadUrl = await createUploadUrl(key, request.contentType, request.sizeBytes);
  return { ok: true as const, fileId, uploadUrl };
}

/**
 * Step 2 of an upload: the browser says it finished. The server checks
 * that the bucket really has the file, with the approved size and type, before
 * showing it. A mismatch deletes the upload.
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

/** A short-lived link to view or download a finished file, or null. */
export async function getDownloadUrl(userId: string, fileId: string, asAttachment: boolean) {
  if (!isUuid(fileId)) return null;
  const [file] = await db
    .select()
    .from(files)
    .where(and(eq(files.id, fileId), eq(files.userId, userId), eq(files.status, "ready")))
    .limit(1);
  if (!file) return null;
  return createDownloadUrl(file.storageKey, {
    contentType: file.mimeType,
    fileName: file.originalName,
    asAttachment,
  });
}

/* ------------------------------------------------------------------ */
/* Deletes                                                             */
/* ------------------------------------------------------------------ */

/**
 * Deletes an entry and its files. The files move to deleted_objects and
 * stay in the bucket for RETENTION_DAYS. Both statements run as one transaction,
 * so a file is never lost track of halfway.
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
 * Housekeeping, run in the background after uploads and deletes:
 * 1. Uploads never confirmed within a day are abandoned. They're queued
 *    for immediate removal, since there's nothing worth recovering.
 * 2. Deleted files older than the retention period are removed from the bucket
 *    for good.
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
  const keys = expired.rows.map((row) => row.storage_key);
  const removed = await deleteObjects(keys);
  if (removed.length > 0) {
    await db.delete(deletedObjects).where(inArray(deletedObjects.storageKey, removed));
  }
  return { removed: removed.length };
}
