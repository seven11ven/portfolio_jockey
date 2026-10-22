import { NextResponse } from "next/server";
import { apiError, authorize } from "@/lib/api";
import { completeUpload } from "@/lib/storage";

/**
 * POST /api/uploads/{fileId}/complete
 * Called after the browser finishes uploading to R2. The server checks the
 * file in R2 before it appears in the app.
 */
export async function POST(request: Request, ctx: RouteContext<"/api/uploads/[fileId]/complete">) {
  const { user, response } = await authorize(request, { checkOrigin: true });
  if (!user) return response;

  const { fileId } = await ctx.params;
  const result = await completeUpload(user.id, fileId);
  if (!result.ok) return apiError(result.status, result.code, result.message);

  return NextResponse.json({ fileId: result.fileId }, { headers: { "Cache-Control": "no-store" } });
}
