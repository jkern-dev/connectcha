// send-push (plan 3.5): called by the push_outbox database webhook with
// { outbox_id }. Loads the recipient's notification settings and device
// tokens, builds the APNs payload and sends it.
//
// APNS_MODE=stub   records what would be sent in push_deliveries; the demo
//                  bridge (scripts/push-bridge.sh) delivers those to the
//                  simulators with `xcrun simctl push`, so banners really show.
// APNS_MODE=apns   signs a JWT with the .p8 key and calls APNs over HTTP/2.
//
// The payload carries the type, ids and the actor's *profile* name with
// mutable-content so the on-device extension can swap in the saved contact
// name (G1). Nothing here ever logs or forwards message bodies.
import { serviceClient } from "../_shared/supabase.ts";
import { error, json } from "../_shared/http.ts";
import { buildPayload, categoryFor, PushType } from "./payload.ts";
import { sendToAPNs } from "./apns.ts";

interface Job {
  outbox: { id: number; recipient_id: string; type: PushType; payload: Record<string, unknown>; sent_at: string | null };
  settings: { requests: boolean; messages: boolean; likes: boolean; bells: boolean } | null;
  tokens: { token: string; platform: "ios" | "ios_simulator" }[];
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return error("method_not_allowed", 405);
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) return error("forbidden", 403);

  let body: { outbox_id?: number; record?: { id?: number } };
  try {
    body = await req.json();
  } catch {
    return error("bad_json");
  }
  const outboxId = body.outbox_id ?? body.record?.id;
  if (typeof outboxId !== "number") return error("bad_outbox_id");

  const supabase = serviceClient();
  const { data, error: jobError } = await supabase.rpc("push_job", { p_outbox_id: outboxId });
  if (jobError || !data) {
    console.error("send-push: job load failed", outboxId, jobError?.code);
    return error("job_failed", 500);
  }
  const job = data as Job;
  if (job.outbox.sent_at) return json({ skipped: "already_sent" });

  // Spec 10 settings: a category that is off sends nothing (still marked sent).
  const category = categoryFor(job.outbox.type);
  const enabled = job.settings ? job.settings[category] : true;
  if (!enabled || job.tokens.length === 0) {
    await supabase.rpc("push_mark_sent", { p_outbox_id: outboxId, p_deliveries: [], p_dead_tokens: [] });
    return json({ skipped: enabled ? "no_tokens" : "category_off" });
  }

  const payload = buildPayload(job.outbox.type, job.outbox.payload);
  const mode = Deno.env.get("APNS_MODE") ?? "stub";
  const deliveries: { token: string; platform: string; payload: unknown }[] = [];
  const dead: string[] = [];

  for (const device of job.tokens) {
    if (mode === "apns" && device.platform === "ios") {
      const result = await sendToAPNs(device.token, payload);
      if (result === "sent") deliveries.push({ token: device.token, platform: device.platform, payload });
      else if (result === "dead") dead.push(device.token);
    } else {
      deliveries.push({ token: device.token, platform: device.platform, payload });
    }
  }

  await supabase.rpc("push_mark_sent", { p_outbox_id: outboxId, p_deliveries: deliveries, p_dead_tokens: dead });
  console.log(`send-push: outbox ${outboxId} type ${job.outbox.type} devices ${job.tokens.length} sent ${deliveries.length} dead ${dead.length}`);
  return json({ sent: deliveries.length, dead: dead.length });
});
