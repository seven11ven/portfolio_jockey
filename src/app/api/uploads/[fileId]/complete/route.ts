import { NextResponse } from "next/server";
import { apiError, authorize } from "@/lib/api";
import { completeUpload } from "@/lib/storage";

/**
 * POST /api/uploads/{fileId}/complete
 * Step 3 of an upload, called after the browser finishes uploading to the
 * Blob store. The server checks the file in the store before it appears in the app.
 */
export async function POST(request: Request, ctx: RouteContext<"/api/uploads/[fileId]/complete">) {
  const { user, response } = await authorize(request, { checkOrigin: true });
  if (!user) return response;

  const { fileId } = await ctx.params;
  const result = await completeUpload(user.id, fileId);
  if (!result.ok) return apiError(result.status, result.code, result.message);

  return NextResponse.json({ fileId: result.fileId }, { headers: { "Cache-Control": "no-store" } });
}
