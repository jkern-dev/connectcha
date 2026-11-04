// APNs payload construction (pure, unit-tested).

export type PushType = "follow_request" | "request_approved" | "message" | "bell_post" | "bell_story";
export type Category = "requests" | "messages" | "likes" | "bells";

export function categoryFor(type: PushType): Category {
  switch (type) {
    case "follow_request":
    case "request_approved":
      return "requests";
    case "message":
      return "messages";
    case "bell_post":
    case "bell_story":
      return "bells";
  }
}

/**
 * The alert text the server can produce: profile name only (the device may
 * replace it). The words follow DESIGN_DIRECTION.md: photos, snapshots,
 * letters, "let you in"; never post, story, message or approve.
 */
export function alertText(type: PushType, actorName: string, extra: Record<string, unknown>): { title: string; body: string } {
  switch (type) {
    case "follow_request":
      return extra.source === "follow_back"
        ? { title: "Connectcha", body: `${actorName} let you in and asked to follow you back` }
        : { title: "Connectcha", body: `${actorName} asked to see your photos` };
    case "request_approved":
      return { title: "Connectcha", body: `${actorName} let you in` };
    case "message":
      switch (extra.kind) {
        case "post_response": return { title: "Connectcha", body: `${actorName} wrote back about your photo` };
        case "story_response": return { title: "Connectcha", body: `${actorName} wrote back about your snapshot` };
        case "story_reaction": return { title: "Connectcha", body: `${actorName} reacted to your snapshot` };
        default: return { title: "Connectcha", body: `${actorName} wrote to you` };
      }
    case "bell_post":
      return { title: "Connectcha", body: `${actorName} shared a photo` };
    case "bell_story":
      return { title: "Connectcha", body: `${actorName} put up a snapshot` };
  }
}

const ALLOWED_KEYS = new Set([
  "type", "actor_id", "actor_name", "request_id", "post_id", "story_id", "conversation_id", "message_id", "source", "kind",
]);

/**
 * Builds the APNs JSON. Only whitelisted keys travel; anything else in the
 * outbox payload (there shouldn't be anything) is dropped.
 */
export function buildPayload(type: PushType, raw: Record<string, unknown>) {
  const actorName = typeof raw.actor_name === "string" && raw.actor_name.trim() ? raw.actor_name : "Someone";
  const custom: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (ALLOWED_KEYS.has(k) && (typeof v === "string" || typeof v === "number")) custom[k] = v;
  }
  custom.type = type;
  const alert = alertText(type, actorName, raw);
  return {
    aps: {
      alert,
      sound: "default",
      "mutable-content": 1,
      "thread-id": type === "message" && typeof raw.conversation_id === "string" ? raw.conversation_id : type,
    },
    ...custom,
    // The template the extension re-renders with the saved contact name.
    body_template: alert.body.replace(actorName, "{name}"),
  };
}
