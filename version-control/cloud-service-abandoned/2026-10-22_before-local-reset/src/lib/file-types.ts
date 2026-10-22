/**
 * Which files can be uploaded, and how big they can be.
 *
 * This file has no secrets, so both the server and the browser can use it.
 * The server always re-checks these rules. The browser only uses them to
 * warn early.
 *
 * SVG and HTML are deliberately NOT allowed, because they can contain
 * scripts.
 */

/** 500 MB per file, approved by the project manager. */
export const MAX_FILE_BYTES = 500 * 1024 * 1024;

export const ALLOWED_MIME_TYPES = [
  // Images
  "image/jpeg",
  "image/png",
  "image/gif",
  "image/webp",
  "image/avif",
  "image/heic",
  "image/heif",
  // Audio
  "audio/mpeg",
  "audio/mp4",
  "audio/x-m4a",
  "audio/aac",
  "audio/wav",
  "audio/x-wav",
  "audio/ogg",
  "audio/webm",
  "audio/flac",
  // Video
  "video/mp4",
  "video/webm",
  "video/quicktime",
  "video/ogg",
  // Documents
  "application/pdf",
  "text/plain",
  "text/markdown",
  "text/csv",
] as const;

export type AllowedMimeType = (typeof ALLOWED_MIME_TYPES)[number];

export function isAllowedMimeType(type: string): type is AllowedMimeType {
  return (ALLOWED_MIME_TYPES as readonly string[]).includes(type);
}

/** Broad category, used to choose how a file is previewed. */
export function fileKind(type: string): "image" | "audio" | "video" | "pdf" | "text" | "other" {
  if (type.startsWith("image/")) return "image";
  if (type.startsWith("audio/")) return "audio";
  if (type.startsWith("video/")) return "video";
  if (type === "application/pdf") return "pdf";
  if (type.startsWith("text/")) return "text";
  return "other";
}

/**
 * Cleans a file name for storage and display: removes folder parts and
 * control characters, and limits the length. The name is only ever shown
 * to the user. It's never used as the storage key.
 */
export function cleanFileName(name: string): string {
  const base = name.split(/[\\/]/).pop() ?? "";
  const cleaned = base.replace(/[\u0000-\u001f\u007f]/g, "").trim();
  return (cleaned || "file").slice(0, 255);
}
