import { handleUploadPresigned, type HandleUploadPresignedBody } from "@vercel/blob/client";
import { NextResponse } from "next/server";
import { apiError, authorize } from "@/lib/api";
import { authorizeUpload, UploadNotAllowedError } from "@/lib/storage";

/**
 * POST /api/uploads/permission
 * Step 2 of an upload. The Blob SDK's uploadPresigned() calls this to get
 * a signed upload link. It only grants one for the signed-in user's own
 * pending file (clientPayload = fileId), at the approved pathname, type
 * and size.
 *
 * Vercel's optional "upload completed" webhook isn't used. The app checks
 * finished uploads itself in POST /api/uploads/{fileId}/complete.
 */
export async function POST(request: Request) {
  const { user, response } = await authorize(request, { checkOrigin: true });
  if (!user) return response;

  const body = (await request.json().catch(() => null)) as HandleUploadPresignedBody | null;
  // Only accept requests for an upload link. Anything else is refused.
  if (body?.type !== "blob.generate-presigned-url") {
    return apiError(400, "invalid_request", "The upload request is invalid.");
  }

  try {
    const result = await handleUploadPresigned({
      body,
      request,
      getSignedToken: (pathname, clientPayload, multipart) =>
        authorizeUpload(user.id, clientPayload ?? "", pathname, multipart),
    });
    return NextResponse.json(result, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    if (error instanceof UploadNotAllowedError) {
      return apiError(403, "upload_not_allowed", "This upload isn't allowed. Start it again.");
    }
    throw error;
  }
}
