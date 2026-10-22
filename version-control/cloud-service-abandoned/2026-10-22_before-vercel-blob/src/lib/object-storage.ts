import "server-only";
import {
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { env } from "@/lib/env";

/**
 * File storage in a private bucket on an S3-compatible service.
 * The project uses Backblaze B2, but any service that speaks the Amazon S3
 * protocol works, because this file only uses the standard AWS S3 SDK.
 *
 * The bucket is private. Browsers never get the keys. They only get
 * short-lived "presigned" links, each allowing one specific action on one
 * specific file.
 */

/** How long an upload link works. */
const UPLOAD_LINK_SECONDS = 15 * 60;
/** How long a view or download link works. */
const DOWNLOAD_LINK_SECONDS = 10 * 60;

let client: S3Client | undefined;

function s3(): S3Client {
  client ??= new S3Client({
    region: env().STORAGE_REGION,
    endpoint: env().STORAGE_ENDPOINT,
    // Put the bucket name in the path (endpoint/bucket/key) instead of the
    // hostname. Backblaze B2 and local test servers both support it.
    forcePathStyle: true,
    credentials: {
      accessKeyId: env().STORAGE_ACCESS_KEY_ID,
      secretAccessKey: env().STORAGE_SECRET_ACCESS_KEY,
    },
    // Newer AWS SDKs add checksum fields to every request by default.
    // Browsers uploading through a presigned link can't send those, so
    // only add them when an operation truly requires them.
    requestChecksumCalculation: "WHEN_REQUIRED",
    responseChecksumValidation: "WHEN_REQUIRED",
  });
  return client;
}

/**
 * A link the browser can PUT one file to.
 * The size and type are part of the signature, so storage rejects an upload
 * that's bigger, smaller, or a different type than what was approved.
 */
export function createUploadUrl(key: string, contentType: string, sizeBytes: number) {
  return getSignedUrl(
    s3(),
    new PutObjectCommand({
      Bucket: env().STORAGE_BUCKET,
      Key: key,
      ContentType: contentType,
      ContentLength: sizeBytes,
    }),
    {
      expiresIn: UPLOAD_LINK_SECONDS,
      signableHeaders: new Set(["content-type", "content-length"]),
    },
  );
}

/**
 * A link to view or download one file.
 * The response type and file name are fixed by the server, not taken
 * from whatever is stored, so a file can't pretend to be something else.
 */
export function createDownloadUrl(
  key: string,
  options: { contentType: string; fileName: string; asAttachment: boolean },
) {
  return getSignedUrl(
    s3(),
    new GetObjectCommand({
      Bucket: env().STORAGE_BUCKET,
      Key: key,
      ResponseContentType: options.contentType,
      ResponseContentDisposition: contentDisposition(options.fileName, options.asAttachment),
      ResponseCacheControl: "private, max-age=600",
    }),
    { expiresIn: DOWNLOAD_LINK_SECONDS },
  );
}

/** Size and type of a stored file, or null if it doesn't exist. */
export async function getObjectInfo(key: string) {
  try {
    const head = await s3().send(new HeadObjectCommand({ Bucket: env().STORAGE_BUCKET, Key: key }));
    return { sizeBytes: head.ContentLength ?? 0, contentType: head.ContentType ?? "" };
  } catch (error) {
    const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode;
    if (status === 404) return null;
    throw error;
  }
}

/**
 * Permanently deletes objects, up to 1000 per call.
 * Returns the keys storage confirmed as deleted. Deleting a key that doesn't
 * exist counts as success.
 *
 * On Backblaze B2 this "hides" the file. The bucket's lifecycle setting
 * "Keep only the last version" then erases it about a day later.
 */
export async function deleteObjects(keys: string[]): Promise<string[]> {
  if (keys.length === 0) return [];
  const result = await s3().send(
    new DeleteObjectsCommand({
      Bucket: env().STORAGE_BUCKET,
      Delete: { Objects: keys.map((Key) => ({ Key })), Quiet: true },
    }),
  );
  const failed = new Set((result.Errors ?? []).map((e) => e.Key));
  return keys.filter((key) => !failed.has(key));
}

/** Builds a Content-Disposition header that's safe for any file name. */
function contentDisposition(fileName: string, asAttachment: boolean) {
  const type = asAttachment ? "attachment" : "inline";
  // Plain-ASCII fallback for old clients, plus the exact UTF-8 name.
  const ascii = fileName.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  const utf8 = encodeURIComponent(fileName).replace(/['()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
  return `${type}; filename="${ascii}"; filename*=UTF-8''${utf8}`;
}
