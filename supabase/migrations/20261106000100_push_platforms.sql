-- Push token platforms (D-33).
--
-- A Debug build installed from Xcode carries a development push entitlement
-- and receives a *sandbox* APNs token; TestFlight and App Store builds receive
-- a *production* one. The two APNs servers reject each other's tokens, so the
-- platform records which server a token belongs to and send-push picks the
-- host per token:
--   ios            production APNs (TestFlight, App Store)
--   ios_sandbox    sandbox APNs (Debug builds on a phone)
--   ios_simulator  never sent to APNs; delivered by the demo bridge (D-27)

alter table public.device_tokens drop constraint device_tokens_platform_check;
alter table public.device_tokens
  add constraint device_tokens_platform_check
  check (platform in ('ios', 'ios_sandbox', 'ios_simulator'));
