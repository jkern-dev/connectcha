import { assert, assertEquals } from "jsr:@std/assert@1";
import { buildPayload, categoryFor } from "./payload.ts";

Deno.test("categories match the spec 10 settings", () => {
  assertEquals(categoryFor("follow_request"), "requests");
  assertEquals(categoryFor("request_approved"), "requests");
  assertEquals(categoryFor("message"), "messages");
  assertEquals(categoryFor("bell_post"), "bells");
  assertEquals(categoryFor("bell_story"), "bells");
});

Deno.test("payload carries the profile name, a template and mutable-content, and nothing else", () => {
  const p = buildPayload("follow_request", {
    type: "follow_request", actor_id: "u1", actor_name: "Linda Kern", request_id: "r1", source: "contact",
    phone: "+15550000002", body: "secret", hash: "abc",
  }) as Record<string, unknown>;
  const aps = p.aps as Record<string, unknown>;
  assertEquals(aps["mutable-content"], 1);
  assertEquals((aps.alert as Record<string, string>).body, "Linda Kern asked to see your photos");
  assertEquals(p.body_template, "{name} asked to see your photos");
  assertEquals(p.actor_name, "Linda Kern");
  assert(!("phone" in p) && !("body" in p) && !("hash" in p), "unexpected keys are dropped");
});

Deno.test("message pushes never include the message text", () => {
  const p = buildPayload("message", { actor_id: "u1", actor_name: "Ana Silva", conversation_id: "c1", message_id: "m1", kind: "post_response" }) as Record<string, unknown>;
  const text = JSON.stringify(p);
  assert(!text.includes("secret"));
  assertEquals(((p.aps as Record<string, unknown>).alert as Record<string, string>).body, "Ana Silva wrote back about your photo");
  assertEquals((p.aps as Record<string, unknown>)["thread-id"], "c1");
});

Deno.test("follow-back requests are phrased as such", () => {
  const p = buildPayload("follow_request", { actor_name: "Ben Carter", source: "follow_back" }) as Record<string, unknown>;
  assertEquals(((p.aps as Record<string, unknown>).alert as Record<string, string>).body, "Ben Carter let you in and asked to follow you back");
});

Deno.test("every banner uses the app's words, never post, story, message or approve", () => {
  const cases: Array<[Parameters<typeof buildPayload>[0], Record<string, unknown>]> = [
    ["follow_request", { source: "contact" }], ["follow_request", { source: "follow_back" }], ["request_approved", {}],
    ["message", { kind: "post_response" }], ["message", { kind: "story_response" }], ["message", { kind: "story_reaction" }],
    ["message", {}], ["bell_post", {}], ["bell_story", {}],
  ];
  for (const [type, extra] of cases) {
    const p = buildPayload(type, { actor_name: "Ana Silva", ...extra }) as Record<string, unknown>;
    const body = ((p.aps as Record<string, unknown>).alert as Record<string, string>).body;
    assert(!/\b(post|story|message|approved?)\b/i.test(body), `${type} ${JSON.stringify(extra)}: ${body}`);
    assert(body.startsWith("Ana Silva "), body);
    assertEquals(p.body_template, body.replace("Ana Silva", "{name}"));
  }
});
