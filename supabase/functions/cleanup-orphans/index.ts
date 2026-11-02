// cleanup-orphans (plan 3.5): deletes bucket objects whose media rows are gone
// (deleted posts and stories, abandoned uploads older than a day).
//
// Scheduled daily in production (Supabase cron → this function). Locally it
// can be invoked by hand: `make cleanup-orphans`. It is protected by the same
// shared secret as send-push so nobody can trigger it from outside.
import { serviceClient } from "../_shared/supabase.ts";
import { S3Signer, s3ConfigFromEnv } from "../_shared/s3.ts";
import { error, json } from "../_shared/http.ts";

/** Keys present in the bucket but referenced by no media row. */
export function orphanKeys(bucketKeys: string[], referencedKeys: Iterable<string>): string[] {
  const referenced = new Set(referencedKeys);
  return bucketKeys.filter((k) => k.startsWith("media/") && !referenced.has(k));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return error("method_not_allowed", 405);
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) return error("forbidden", 403);

  const supabase = serviceClient();
  const { data, error: dbError } = await supabase.from("media").select("object_key, thumb_key");
  if (dbError) {
    console.error("cleanup-orphans: query failed", dbError.code);
    return error("query_failed", 500);
  }
  const referenced: string[] = [];
  for (const row of data ?? []) {
    referenced.push(row.object_key);
    if (row.thumb_key) referenced.push(row.thumb_key);
  }

  const signer = new S3Signer(s3ConfigFromEnv());
  const keys = await signer.listKeys("media/");
  const orphans = orphanKeys(keys, referenced);
  let deleted = 0;
  for (const key of orphans) {
    const status = await signer.deleteObject(key);
    if (status === 204 || status === 200) deleted += 1;
  }
  console.log(`cleanup-orphans: scanned ${keys.length}, referenced ${referenced.length}, deleted ${deleted}`);
  return json({ scanned: keys.length, orphans: orphans.length, deleted });
});
