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

/** The alert text the server can produce: profile name only (the device may replace it). */
export function alertText(type: PushType, actorName: string, extra: Record<string, unknown>): { title: string; body: string } {
  switch (type) {
    case "follow_request":
      return extra.source === "follow_back"
        ? { title: "Connectcha", body: `${actorName} approved you and wants to follow you back` }
        : { title: "Connectcha", body: `${actorName} wants to follow you` };
    case "request_approved":
      return { title: "Connectcha", body: `${actorName} approved your request` };
    case "message":
      switch (extra.kind) {
        case "post_response": return { title: "Connectcha", body: `${actorName} responded to your post` };
        case "story_response": return { title: "Connectcha", body: `${actorName} replied to your story` };
        case "story_reaction": return { title: "Connectcha", body: `${actorName} reacted to your story` };
        default: return { title: "Connectcha", body: `${actorName} sent you a message` };
      }
    case "bell_post":
      return { title: "Connectcha", body: `${actorName} shared a new post` };
    case "bell_story":
      return { title: "Connectcha", body: `${actorName} added a story` };
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
