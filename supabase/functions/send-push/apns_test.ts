import { assertEquals } from "jsr:@std/assert@1";
import { apnsHost } from "./apns.ts";

Deno.test("production tokens go to the production APNs host, sandbox tokens to the sandbox host (D-33)", () => {
  assertEquals(apnsHost("ios"), "https://api.push.apple.com");
  assertEquals(apnsHost("ios_sandbox"), "https://api.sandbox.push.apple.com");
});

Deno.test("simulator and unknown platforms are never sent to APNs", () => {
  assertEquals(apnsHost("ios_simulator"), null);
  assertEquals(apnsHost("android"), null);
  assertEquals(apnsHost(""), null);
});
