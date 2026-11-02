// Presigned URL issuance for the private media bucket over the S3 protocol.
// Locally this points at Supabase Storage's S3 endpoint; in production the
// same code points at Cloudflare R2. Only the environment changes.
import { AwsClient } from "npm:aws4fetch@1.0.20";

export interface S3Config {
  /** Endpoint the *client* will use, e.g. http://127.0.0.1:54321/storage/v1/s3 */
  endpoint: string;
  /** Endpoint for calls made from inside the Edge Runtime (listing/deleting). Defaults to endpoint. */
  internalEndpoint: string;
  bucket: string;
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
}

export function s3ConfigFromEnv(env: (k: string) => string | undefined = Deno.env.get): S3Config {
  const required = (k: string) => {
    const v = env(k);
    if (!v) throw new Error(`missing env ${k}`);
    return v;
  };
  const endpoint = required("S3_ENDPOINT").replace(/\/$/, "");
  return {
    endpoint,
    internalEndpoint: (env("S3_INTERNAL_ENDPOINT") ?? endpoint).replace(/\/$/, ""),
    bucket: required("S3_BUCKET"),
    region: env("S3_REGION") ?? "auto",
    accessKeyId: required("S3_ACCESS_KEY_ID"),
    secretAccessKey: required("S3_SECRET_ACCESS_KEY"),
  };
}

export class S3Signer {
  private client: AwsClient;
  constructor(private cfg: S3Config) {
    this.client = new AwsClient({
      accessKeyId: cfg.accessKeyId,
      secretAccessKey: cfg.secretAccessKey,
      region: cfg.region,
      service: "s3",
    });
  }

  private objectUrl(key: string, internal = false): string {
    const base = internal ? this.cfg.internalEndpoint : this.cfg.endpoint;
    // Path-style addressing works for both Supabase Storage and R2.
    return `${base}/${this.cfg.bucket}/${key.split("/").map(encodeURIComponent).join("/")}`;
  }

  /** Presigned URL the client can use with the given method for `expiresSeconds`. */
  async presign(method: "GET" | "PUT", key: string, expiresSeconds: number): Promise<string> {
    const url = new URL(this.objectUrl(key));
    url.searchParams.set("X-Amz-Expires", String(expiresSeconds));
    const signed = await this.client.sign(new Request(url.toString(), { method }), {
      aws: { signQuery: true },
    });
    return signed.url;
  }

  /** Deletes one object from inside the runtime. */
  async deleteObject(key: string): Promise<number> {
    const res = await this.client.fetch(this.objectUrl(key, true), { method: "DELETE" });
    return res.status;
  }

  /** Lists object keys under a prefix (ListObjectsV2, paginated). */
  async listKeys(prefix: string): Promise<string[]> {
    const keys: string[] = [];
    let token: string | undefined;
    do {
      const url = new URL(`${this.cfg.internalEndpoint}/${this.cfg.bucket}`);
      url.searchParams.set("list-type", "2");
      url.searchParams.set("prefix", prefix);
      url.searchParams.set("max-keys", "1000");
      if (token) url.searchParams.set("continuation-token", token);
      const res = await this.client.fetch(url.toString(), { method: "GET" });
      if (!res.ok) throw new Error(`list failed: ${res.status}`);
      const xml = await res.text();
      for (const m of xml.matchAll(/<Key>([^<]+)<\/Key>/g)) keys.push(decodeXml(m[1]));
      const next = xml.match(/<NextContinuationToken>([^<]+)<\/NextContinuationToken>/);
      token = next ? decodeXml(next[1]) : undefined;
    } while (token);
    return keys;
  }
}

function decodeXml(s: string): string {
  return s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
}
