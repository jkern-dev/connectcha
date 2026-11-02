import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1";
import { S3Signer, s3ConfigFromEnv } from "./s3.ts";

const cfg = {
  endpoint: "http://127.0.0.1:54321/storage/v1/s3",
  internalEndpoint: "http://kong:8000/storage/v1/s3",
  bucket: "media",
  region: "local",
  accessKeyId: "AKIATEST",
  secretAccessKey: "secret",
};

Deno.test("presigned URLs carry a query signature, the client endpoint and the expiry", async () => {
  const signer = new S3Signer(cfg);
  const url = new URL(await signer.presign("GET", "media/owner-1/abc.jpg", 3600));
  assertEquals(url.origin + url.pathname, "http://127.0.0.1:54321/storage/v1/s3/media/media/owner-1/abc.jpg");
  assertEquals(url.searchParams.get("X-Amz-Expires"), "3600");
  assertMatch(url.searchParams.get("X-Amz-Signature") ?? "", /^[0-9a-f]{64}$/);
  assert(url.searchParams.get("X-Amz-Credential")?.startsWith("AKIATEST/"));
});

Deno.test("PUT and GET signatures differ for the same key", async () => {
  const signer = new S3Signer(cfg);
  const put = new URL(await signer.presign("PUT", "media/o/x.mp4", 900));
  const get = new URL(await signer.presign("GET", "media/o/x.mp4", 900));
  assert(put.searchParams.get("X-Amz-Signature") !== get.searchParams.get("X-Amz-Signature"));
});

Deno.test("config falls back to the client endpoint for internal calls and region auto", () => {
  const env: Record<string, string> = {
    S3_ENDPOINT: "https://acct.r2.cloudflarestorage.com/",
    S3_BUCKET: "connectcha-media",
    S3_ACCESS_KEY_ID: "k",
    S3_SECRET_ACCESS_KEY: "s",
  };
  const c = s3ConfigFromEnv((k) => env[k]);
  assertEquals(c.endpoint, "https://acct.r2.cloudflarestorage.com");
  assertEquals(c.internalEndpoint, c.endpoint);
  assertEquals(c.region, "auto");
});
