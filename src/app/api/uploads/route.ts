import { after, NextResponse } from "next/server";
import { z } from "zod";
import { apiError, authorize } from "@/lib/api";
import { cleanUpStorage, createUpload } from "@/lib/storage";

const UploadRequest = z.object({
  entryId: z.uuid(),
  fileName: z.string().min(1).max(1024),
  contentType: z.string().min(1).max(255),
  sizeBytes: z.number().int().positive(),
});

/**
 * POST /api/uploads
 * Starts an upload. Returns { fileId, uploadUrl }. The browser then PUTs
 * the file to uploadUrl with the same Content-Type, and calls
 * POST /api/uploads/{fileId}/complete.
 */
export async function POST(request: Request) {
  const { user, response } = await authorize(request, { checkOrigin: true });
  if (!user) return response;

  const body = UploadRequest.safeParse(await request.json().catch(() => null));
  if (!body.success) return apiError(400, "invalid_request", "The upload request is invalid.");

  const result = await createUpload(user.id, body.data);
  if (!result.ok) return apiError(result.status, result.code, result.message);

  // Tidy up abandoned uploads and expired deletes after responding.
  after(() => cleanUpStorage().catch((error) => console.error("Storage cleanup failed:", error)));

  return NextResponse.json(
    { fileId: result.fileId, uploadUrl: result.uploadUrl },
    { status: 201, headers: { "Cache-Control": "no-store" } },
  );
}
