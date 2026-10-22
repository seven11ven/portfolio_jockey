import "server-only";
import {
  BlobNotFoundError,
  del,
  head,
  issueSignedToken,
  presignUrl,
  type IssuedSignedToken,
} from "@vercel/blob";

/**
 * File storage in a PRIVATE Vercel Blob store.
 *
 * Nothing in the store is public. Browsers never get the store's
 * credentials. They only get short-lived "signed" links, each allowing one
 * action (upload, view) on one file. Signing happens here on the server.
 *
 * The Blob SDK finds its credentials by itself: BLOB_READ_WRITE_TOKEN
 * locally, or the store connection (OIDC) when running on Vercel.
 * See src/lib/env.ts and docs/setup/03-vercel-blob.md.
 */

/** Files bigger than this are uploaded in parts, as Vercel recommends. */
export const MULTIPART_THRESHOLD_BYTES = 100 * 1024 * 1024;
/** Part size the Blob SDK uses for multipart uploads (8 MiB). */
export const MULTIPART_PART_BYTES = 8 * 1024 * 1024;

/** How long an upload permission lasts. */
const UPLOAD_TOKEN_MS = 15 * 60 * 1000;
/** How long a view or download link works. */
const VIEW_LINK_MS = 10 * 60 * 1000;
/** How long the server's shared read token lasts (the maximum is 7 days). */
const READ_TOKEN_MS = 24 * 60 * 60 * 1000;
/** Renew the read token when it has less than this left. */
const READ_TOKEN_RENEW_MS = 60 * 60 * 1000;

/**
 * Upload permission for exactly one pathname, one content type, and at
 * most the approved size. Vercel enforces these limits on the upload itself.
 */
export async function issueUploadPermission(pathname: string, contentType: string, sizeBytes: number) {
  const validUntil = Date.now() + UPLOAD_TOKEN_MS;
  const token = await issueSignedToken({
    pathname,
    operations: ["put"],
    allowedContentTypes: [contentType],
    maximumSizeInBytes: sizeBytes,
    validUntil,
  });
  return {
    token,
    urlOptions: {
      allowedContentTypes: [contentType],
      maximumSizeInBytes: sizeBytes,
      validUntil,
      // The pathname is already unique, so never rename or overwrite.
      addRandomSuffix: false,
      allowOverwrite: false,
    },
  };
}

/*
 * One read-only token, kept in server memory and reused to sign view links.
 * Issuing a token is a call to Vercel, so reusing it saves time and stays
 * well inside the free allowance. The secret half of it never leaves the
 * server. Each link it signs is limited to one file and 10 minutes.
 */
let readToken: IssuedSignedToken | undefined;

/** True when the next view link will need a fresh read token from Vercel. */
export function readTokenNeedsRenewal() {
  return !readToken || readToken.validUntil - Date.now() < READ_TOKEN_RENEW_MS;
}

async function getReadToken() {
  if (readTokenNeedsRenewal()) {
    readToken = await issueSignedToken({
      pathname: "*",
      operations: ["get"],
      validUntil: Date.now() + READ_TOKEN_MS,
    });
  }
  return readToken!;
}

/**
 * A link to view one file for 10 minutes, fetched straight from the store
 * (no app server in between, so large videos and seeking work).
 * `asAttachment` asks the browser to save the file instead of showing it.
 */
export async function createViewUrl(pathname: string, asAttachment: boolean) {
  const { presignedUrl } = await presignUrl(await getReadToken(), {
    operation: "get",
    pathname,
    access: "private",
    validUntil: Date.now() + VIEW_LINK_MS,
  });
  if (!asAttachment) return presignedUrl;
  const url = new URL(presignedUrl);
  url.searchParams.set("download", "1");
  return url.toString();
}

/** Size and type of a stored file, or null if it doesn't exist. */
export async function getObjectInfo(pathname: string) {
  try {
    const blob = await head(pathname);
    return { sizeBytes: blob.size, contentType: blob.contentType };
  } catch (error) {
    if (error instanceof BlobNotFoundError) return null;
    throw error;
  }
}

/**
 * Permanently deletes files. Deleting is free on Vercel Blob, and deleting
 * a file that doesn't exist isn't an error. Returns the pathnames deleted.
 */
export async function deleteObjects(pathnames: string[]): Promise<string[]> {
  const deleted: string[] = [];
  for (let i = 0; i < pathnames.length; i += 100) {
    const batch = pathnames.slice(i, i + 100);
    await del(batch);
    deleted.push(...batch);
  }
  return deleted;
}
