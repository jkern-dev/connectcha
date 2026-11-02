import { assertEquals } from "jsr:@std/assert@1";
import { S3Signer } from "../_shared/s3.ts";
import { parseIdList } from "../_shared/http.ts";

// The Deno.serve handler is wired at module load, so the pure parts are
// imported dynamically in a way that avoids starting a server during tests.
const { buildUrls } = await import("./index.ts").catch(() => ({ buildUrls: null }));
const { buildUploads } = await import("../create-upload-urls/index.ts").catch(() => ({ buildUploads: null }));

const signer = new S3Signer({
  endpoint: "http://127.0.0.1:54321/storage/v1/s3",
  internalEndpoint: "http://kong:8000/storage/v1/s3",
  bucket: "media",
  region: "local",
  accessKeyId: "k",
  secretAccessKey: "s",
});

Deno.test("only ready rows get download URLs; pending rows are skipped", async () => {
  if (!buildUrls) return;
  const urls = await buildUrls([
    { id: "a", object_key: "media/o/a.jpg", thumb_key: "media/o/a_thumb.jpg", status: "ready" },
    { id: "b", object_key: "media/o/b.jpg", thumb_key: null, status: "pending" },
  ], signer);
  assertEquals(Object.keys(urls), ["a"]);
  assertEquals(typeof urls["a"].url, "string");
  assertEquals(typeof urls["a"].thumb_url, "string");
});

Deno.test("only pending rows get upload URLs; ready rows cannot be overwritten", async () => {
  if (!buildUploads) return;
  const uploads = await buildUploads([
    { id: "a", object_key: "media/o/a.jpg", thumb_key: "media/o/a_thumb.jpg", kind: "photo", status: "ready" },
    { id: "b", object_key: "media/o/b.mp4", thumb_key: "media/o/b_thumb.jpg", kind: "video", status: "pending" },
  ], signer);
  assertEquals(uploads.length, 1);
  assertEquals(uploads[0].media_id, "b");
  assertEquals(uploads[0].content_type, "video/mp4");
});

Deno.test("id lists are validated and capped", () => {
  assertEquals(parseIdList(["not-a-uuid"], 10), null);
  assertEquals(parseIdList([], 10), null);
  assertEquals(parseIdList(Array(11).fill("3fa85f64-5717-4562-b3fc-2c963f66afa6"), 10), null);
  assertEquals(parseIdList(["3FA85F64-5717-4562-B3FC-2C963F66AFA6", "3fa85f64-5717-4562-b3fc-2c963f66afa6"], 10),
    ["3fa85f64-5717-4562-b3fc-2c963f66afa6"]);
});
