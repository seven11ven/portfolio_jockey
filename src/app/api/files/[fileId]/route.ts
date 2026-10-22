import { NextResponse } from "next/server";
import { apiError, authorize } from "@/lib/api";
import { getDownloadUrl } from "@/lib/storage";

/**
 * GET /api/files/{fileId}            -> view in the browser
 * GET /api/files/{fileId}?download=1 -> save as a file
 *
 * Checks that the file belongs to the signed-in user, then redirects to a
 * link that works for 10 minutes. Pages can use this address directly in
 * <img>, <audio> and <video> tags.
 */
export async function GET(request: Request, ctx: RouteContext<"/api/files/[fileId]">) {
  // Reading a file doesn't change data, so no origin check is needed, and
  // <img> tags don't send an Origin header anyway.
  const { user, response } = await authorize(request, { checkOrigin: false });
  if (!user) return response;

  const { fileId } = await ctx.params;
  const asAttachment = new URL(request.url).searchParams.get("download") === "1";
  const url = await getDownloadUrl(user.id, fileId, asAttachment);
  // Same answer for "doesn't exist" and "not yours", so ids can't be probed.
  if (!url) return apiError(404, "file_not_found", "That file doesn't exist.");

  return NextResponse.redirect(url, {
    status: 302,
    headers: { "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer" },
  });
}
