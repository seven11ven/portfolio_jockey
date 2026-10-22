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
 * Cloudflare R2 file storage.
 *
 * R2 speaks the same language as Amazon S3, so the AWS SDK works with it.
 * The bucket is private. Browsers never get the keys. They only get
 * short-lived "presigned" links, each allowing one specific action on one
 * specific file.
 */

/** How long an upload link works. */
const UPLOAD_LINK_SECONDS = 15 * 60;
/** How long a view or download link works. */
const DOWNLOAD_LINK_SECONDS = 10 * 60;

let client: S3Client | undefined;

function r2(): S3Client {
  client ??= new S3Client({
    region: "auto",
    endpoint: env().R2_ENDPOINT ?? `https://${env().R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    // Put the bucket name in the path (account.r2.cloudflarestorage.com/bucket/key)
    // instead of the hostname. R2 and local test servers both support it.
    forcePathStyle: true,
    credentials: {
      accessKeyId: env().R2_ACCESS_KEY_ID,
      secretAccessKey: env().R2_SECRET_ACCESS_KEY,
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
 * The size and type are part of the signature, so R2 rejects an upload
 * that's bigger, smaller, or a different type than what was approved.
 */
export function createUploadUrl(key: string, contentType: string, sizeBytes: number) {
  return getSignedUrl(
    r2(),
    new PutObjectCommand({
      Bucket: env().R2_BUCKET,
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
    r2(),
    new GetObjectCommand({
      Bucket: env().R2_BUCKET,
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
    const head = await r2().send(new HeadObjectCommand({ Bucket: env().R2_BUCKET, Key: key }));
    return { sizeBytes: head.ContentLength ?? 0, contentType: head.ContentType ?? "" };
  } catch (error) {
    const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode;
    if (status === 404) return null;
    throw error;
  }
}

/**
 * Permanently deletes objects, up to 1000 per call.
 * Returns the keys R2 confirmed as deleted. Deleting a key that doesn't
 * exist counts as success.
 */
export async function deleteObjects(keys: string[]): Promise<string[]> {
  if (keys.length === 0) return [];
  const result = await r2().send(
    new DeleteObjectsCommand({
      Bucket: env().R2_BUCKET,
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
