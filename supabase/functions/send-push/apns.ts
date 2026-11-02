// Direct APNs HTTP/2 delivery with a token-signing (.p8) key. Used when
// APNS_MODE=apns and the owner has an Apple Developer account (OPEN_QUESTIONS Q4).

let cachedJwt: { token: string; issuedAt: number } | null = null;

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): Uint8Array {
  const b64 = pem.replace(/-----BEGIN PRIVATE KEY-----/, "").replace(/-----END PRIVATE KEY-----/, "").replace(/\s+/g, "");
  const bin = atob(b64);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/** ES256 provider token, cached for 50 minutes (APNs allows up to an hour). */
async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.issuedAt < 50 * 60) return cachedJwt.token;
  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const pem = Deno.env.get("APNS_PRIVATE_KEY")!.replace(/\\n/g, "\n");
  const key = await crypto.subtle.importKey("pkcs8", pemToPkcs8(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`)));
  const token = `${header}.${claims}.${base64url(signature)}`;
  cachedJwt = { token, issuedAt: now };
  return token;
}

export type APNsResult = "sent" | "dead" | "failed";

export async function sendToAPNs(deviceToken: string, payload: unknown): Promise<APNsResult> {
  const host = (Deno.env.get("APNS_ENVIRONMENT") ?? "sandbox") === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.connectcha.app";
  try {
    const res = await fetch(`${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        "authorization": `bearer ${await providerToken()}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    if (res.ok) return "sent";
    const text = await res.text();
    // 410 Unregistered / BadDeviceToken: forget the token.
    if (res.status === 410 || text.includes("BadDeviceToken") || text.includes("Unregistered")) return "dead";
    console.error("send-push: APNs responded", res.status);
    return "failed";
  } catch (e) {
    console.error("send-push: APNs request failed", (e as Error).message);
    return "failed";
  }
}
