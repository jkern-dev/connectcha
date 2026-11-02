// create-upload-urls (plan 3.5)
//
// Input:  { "media_ids": [uuid, ...] }  (at most 10)
// Output: { "uploads": [{ media_id, upload_url, thumb_upload_url, content_type }] }
//
// The caller must own each media row and it must still be pending. The query
// runs as the caller, so row-level security does the ownership filtering; a
// non-owner simply gets nothing back for that id. URLs expire in 15 minutes.
import { clientForCaller } from "../_shared/supabase.ts";
import { S3Signer, s3ConfigFromEnv } from "../_shared/s3.ts";
import { error, json, parseIdList, subjectOf } from "../_shared/http.ts";

export const UPLOAD_URL_TTL_SECONDS = 15 * 60;

interface MediaRow {
  id: string;
  object_key: string;
  thumb_key: string | null;
  kind: "photo" | "video";
  status: "pending" | "ready";
}

export async function buildUploads(rows: MediaRow[], signer: S3Signer) {
  const uploads = [];
  for (const row of rows) {
    if (row.status !== "pending") continue;
    uploads.push({
      media_id: row.id,
      upload_url: await signer.presign("PUT", row.object_key, UPLOAD_URL_TTL_SECONDS),
      thumb_upload_url: row.thumb_key ? await signer.presign("PUT", row.thumb_key, UPLOAD_URL_TTL_SECONDS) : null,
      content_type: row.kind === "video" ? "video/mp4" : "image/jpeg",
      expires_in: UPLOAD_URL_TTL_SECONDS,
    });
  }
  return uploads;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return error("method_not_allowed", 405);
  const supabase = clientForCaller(req);
  if (!supabase) return error("not_signed_in", 401);

  let body: { media_ids?: unknown };
  try {
    body = await req.json();
  } catch {
    return error("bad_json");
  }
  const ids = parseIdList(body.media_ids, 10);
  if (!ids) return error("bad_media_ids");

  // The owner filter uses the JWT's subject. The query below runs with that
  // same JWT, so a forged token fails there; the claim is only a filter.
  const callerId = subjectOf(req.headers.get("authorization")!);
  if (!callerId) return error("not_signed_in", 401);

  const { data, error: dbError } = await supabase
    .from("media")
    .select("id, object_key, thumb_key, kind, status")
    .in("id", ids)
    .eq("owner_id", callerId);
  if (dbError) {
    console.error("create-upload-urls: query failed", dbError.code);
    return error("query_failed", 500);
  }

  const signer = new S3Signer(s3ConfigFromEnv());
  const uploads = await buildUploads((data ?? []) as MediaRow[], signer);
  return json({ uploads });
});
