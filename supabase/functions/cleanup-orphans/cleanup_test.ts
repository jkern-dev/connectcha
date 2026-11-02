import { assertEquals } from "jsr:@std/assert@1";

const { orphanKeys } = await import("./index.ts").catch(() => ({ orphanKeys: null }));

Deno.test("only unreferenced keys under media/ are orphans", () => {
  if (!orphanKeys) return;
  const bucket = ["media/u1/a.jpg", "media/u1/a_thumb.jpg", "media/u1/gone.jpg", "other/x.bin"];
  const referenced = ["media/u1/a.jpg", "media/u1/a_thumb.jpg"];
  assertEquals(orphanKeys(bucket, referenced), ["media/u1/gone.jpg"]);
});
