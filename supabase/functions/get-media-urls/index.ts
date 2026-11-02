// get-media-urls (plan 3.5)
//
// Input:  { "media_ids": [uuid, ...] }  (at most 100)
// Output: { "urls": { "<media_id>": { url, thumb_url, expires_at } }, "expires_in": seconds }
//
// The media query runs as the caller, so row-level security decides which ids
// come back. Ids the caller may not see are silently absent; that is the whole
// enforcement of "nobody sees posts without approval" at the bytes level.
import { clientForCaller } from "../_shared/supabase.ts";
import { S3Signer, s3ConfigFromEnv } from "../_shared/s3.ts";
import { error, json, parseIdList } from "../_shared/http.ts";

export const MEDIA_URL_TTL_SECONDS = 60 * 60;

interface MediaRow {
  id: string;
  object_key: string;
  thumb_key: string | null;
  status: "pending" | "ready";
}

export async function buildUrls(rows: MediaRow[], signer: S3Signer, now = new Date()) {
  const expiresAt = new Date(now.getTime() + MEDIA_URL_TTL_SECONDS * 1000).toISOString();
  const urls: Record<string, { url: string; thumb_url: string | null; expires_at: string }> = {};
  for (const row of rows) {
    if (row.status !== "ready") continue;
    urls[row.id] = {
      url: await signer.presign("GET", row.object_key, MEDIA_URL_TTL_SECONDS),
      thumb_url: row.thumb_key ? await signer.presign("GET", row.thumb_key, MEDIA_URL_TTL_SECONDS) : null,
      expires_at: expiresAt,
    };
  }
  return urls;
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
  const ids = parseIdList(body.media_ids, 100);
  if (!ids) return error("bad_media_ids");

  // RLS-filtered: only rows the caller may see come back.
  const { data, error: dbError } = await supabase
    .from("media")
    .select("id, object_key, thumb_key, status")
    .in("id", ids);
  if (dbError) {
    console.error("get-media-urls: query failed", dbError.code);
    return error("query_failed", 500);
  }

  const signer = new S3Signer(s3ConfigFromEnv());
  const urls = await buildUrls((data ?? []) as MediaRow[], signer);
  return json({ urls, expires_in: MEDIA_URL_TTL_SECONDS });
});
