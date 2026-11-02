// Small helpers shared by the Edge Functions. Nothing here logs request
// bodies: the only logging in these functions is counts and status codes.

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function error(code: string, status = 400): Response {
  return json({ error: code }, status);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Returns the lower-cased, de-duplicated uuid list or null if the input is malformed. */
export function parseIdList(value: unknown, max: number): string[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > max) return null;
  const out = new Set<string>();
  for (const v of value) {
    if (typeof v !== "string" || !UUID.test(v)) return null;
    out.add(v.toLowerCase());
  }
  return [...out];
}

/** The `sub` claim of a bearer token, without verifying it (the database does that). */
export function subjectOf(authorizationHeader: string): string | null {
  try {
    const token = authorizationHeader.replace(/^bearer\s+/i, "");
    const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = payload + "=".repeat((4 - (payload.length % 4)) % 4);
    const json = new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0)));
    const sub = JSON.parse(json).sub;
    return typeof sub === "string" && UUID.test(sub) ? sub : null;
  } catch {
    return null;
  }
}
