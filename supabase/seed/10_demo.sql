-- Demo personas and pre-arranged state for the two-simulator walkthrough
-- (DEMO.md). Seed only: never shipped to a hosted project.
--
-- People (all sign in with code 123456):
--   josh   +1 555 000 0001  Josh Kern
--   mom    +1 555 000 0002  Linda Kern
--   dad    +1 555 000 0003  Robert Kern
--   ana    +1 555 000 0004  Ana Silva
--   ben    +1 555 000 0005  Ben Carter
--   priya  +1 555 000 0006  Priya Nair
--   sam    +1 555 000 0007  Sam Lee        (nobody follows Sam; a stranger)
--
-- Who follows whom (→ means "follows"):
--   josh → mom, dad, ana          mom → josh, dad      dad → mom
--   ana  → josh, priya            priya → josh, ana, ben   ben → priya
-- Pending requests: dad → josh (incoming for Josh), josh → priya (outgoing).
-- Ana has Ben's number; Ben does not have Ana's (follow-back walkthrough, S3).
--
-- Media object keys follow "media/<user>/demo-<name>.<ext>"; scripts/seed-media.sh
-- uploads the matching files from supabase/seed/media.

-- Seed-only helpers (schema tests is never pushed to production).
create or replace function tests.demo_add_media(owner uuid, post uuid, usage public.media_usage, kind public.media_kind,
                                                name text, w integer, h integer, dur numeric, pos integer)
returns uuid language plpgsql set search_path = '' as $f$
declare mid uuid;
begin
  insert into public.media (owner_id, post_id, usage, kind, object_key, thumb_key, width, height, duration_s, bytes, position, status)
  values (owner, post, usage, kind,
          'media/' || owner || '/demo-' || name || case when kind = 'video' then '.mp4' else '.jpg' end,
          'media/' || owner || '/demo-' || name || '_thumb.jpg',
          w, h, dur, 0, pos, 'ready')
  returning id into mid;
  return mid;
end $f$;

create or replace function tests.demo_add_post(author uuid, caption text, place text, age interval, responses boolean default true)
returns uuid language plpgsql set search_path = '' as $f$
declare pid uuid;
begin
  insert into public.posts (author_id, caption, location_name, responses_enabled, published_at, created_at)
  values (author, caption, place, responses, now() - age, now() - age)
  returning id into pid;
  return pid;
end $f$;

create or replace procedure tests.demo_follow(a uuid, b uuid, age interval)
language plpgsql set search_path = '' as $f$
begin
  insert into public.follows (follower_id, followee_id, created_at) values (a, b, now() - age) on conflict do nothing;
  insert into public.follow_requests (requester_id, target_id, source, status, created_at, resolved_at)
  values (a, b, 'contact', 'approved', now() - age - interval '1 hour', now() - age);
  insert into public.activity (recipient_id, actor_id, type, request_id, created_at)
  select a, b, 'request_approved', id, now() - age from public.follow_requests
   where requester_id = a and target_id = b and status = 'approved' limit 1;
end $f$;

create or replace procedure tests.demo_like(who uuid, post uuid, age interval)
language plpgsql set search_path = '' as $f$
declare author uuid;
begin
  insert into public.likes (post_id, user_id, created_at) values (post, who, now() - age) on conflict do nothing;
  select author_id into author from public.posts where id = post;
  if author <> who then
    insert into public.activity (recipient_id, actor_id, type, post_id, created_at) values (author, who, 'like', post, now() - age);
  end if;
end $f$;

do $$
declare
  josh uuid; mom uuid; dad uuid; ana uuid; ben uuid; priya uuid; sam uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; p6 uuid; p7 uuid; p8 uuid; p9 uuid; p10 uuid; p11 uuid; p12 uuid;
  s_mom uuid; s_ana uuid; s_priya uuid; s_josh uuid; s_josh_old uuid;
  c_josh_mom uuid; c_ana_josh uuid; c_priya_josh uuid;
  m uuid; t timestamptz;

begin
  josh  := tests.create_user('demo_josh',  '15550000001', 'Josh', 'Kern');
  mom   := tests.create_user('demo_mom',   '15550000002', 'Linda', 'Kern');
  dad   := tests.create_user('demo_dad',   '15550000003', 'Robert', 'Kern');
  ana   := tests.create_user('demo_ana',   '15550000004', 'Ana', 'Silva');
  ben   := tests.create_user('demo_ben',   '15550000005', 'Ben', 'Carter');
  priya := tests.create_user('demo_priya', '15550000006', 'Priya', 'Nair');
  sam   := tests.create_user('demo_sam',   '15550000007', 'Sam', 'Lee');

  update public.profiles set bio = 'Dad of two, weekend hiker.' where id = josh;
  update public.profiles set bio = 'Gardener. Grandma. Pie person.' where id = mom;
  update public.profiles set bio = 'Retired. Fixing things.' where id = dad;
  update public.profiles set bio = 'Photos of the coast and my dog.' where id = ana;
  update public.profiles set bio = 'Lakes, bikes, coffee.' where id = ben;
  update public.profiles set bio = 'Cooking my way through the year.' where id = priya;
  insert into public.notification_settings (user_id) select id from public.profiles on conflict do nothing;

  -- Avatars
  m := tests.demo_add_media(josh,  null, 'avatar', 'photo', 'a1', 600, 600, null, 0); update public.profiles set avatar_media_id = m where id = josh;
  m := tests.demo_add_media(mom,   null, 'avatar', 'photo', 'a2', 600, 600, null, 0); update public.profiles set avatar_media_id = m where id = mom;
  m := tests.demo_add_media(ana,   null, 'avatar', 'photo', 'a3', 600, 600, null, 0); update public.profiles set avatar_media_id = m where id = ana;
  m := tests.demo_add_media(ben,   null, 'avatar', 'photo', 'a4', 600, 600, null, 0); update public.profiles set avatar_media_id = m where id = ben;
  m := tests.demo_add_media(priya, null, 'avatar', 'photo', 'a5', 600, 600, null, 0); update public.profiles set avatar_media_id = m where id = priya;

  -- Follow graph
  call tests.demo_follow(josh, mom, interval '40 days');
  call tests.demo_follow(mom, josh, interval '40 days');
  call tests.demo_follow(josh, dad, interval '39 days');
  call tests.demo_follow(mom, dad, interval '39 days');
  call tests.demo_follow(dad, mom, interval '38 days');
  call tests.demo_follow(josh, ana, interval '20 days');
  call tests.demo_follow(ana, josh, interval '20 days');
  call tests.demo_follow(ana, priya, interval '15 days');
  call tests.demo_follow(priya, josh, interval '14 days');
  call tests.demo_follow(priya, ana, interval '14 days');
  call tests.demo_follow(priya, ben, interval '10 days');
  call tests.demo_follow(ben, priya, interval '10 days');

  -- Pending requests
  insert into public.follow_requests (requester_id, target_id, source, status, created_at)
  values (dad, josh, 'contact', 'pending', now() - interval '2 days');
  insert into public.activity (recipient_id, actor_id, type, request_id, created_at)
  select josh, dad, 'follow_request', id, created_at from public.follow_requests where requester_id = dad and target_id = josh and status = 'pending';
  insert into public.follow_requests (requester_id, target_id, source, status, created_at)
  values (josh, priya, 'contact', 'pending', now() - interval '1 day');
  insert into public.activity (recipient_id, actor_id, type, request_id, created_at)
  select priya, josh, 'follow_request', id, created_at from public.follow_requests where requester_id = josh and target_id = priya and status = 'pending';

  -- Bells and feed marker
  insert into public.bells (user_id, target_id) values (josh, mom);
  insert into public.feed_seen (user_id, seen_through) values (josh, now() - interval '3 days');

  -- Posts
  p1 := tests.demo_add_post(mom, 'First tomatoes of the year! The Sungolds won again.', 'Back garden', interval '1 day');
  m := tests.demo_add_media(mom, p1, 'post', 'photo', 'p01', 1600, 1200, null, 0);
  m := tests.demo_add_media(mom, p1, 'post', 'photo', 'p02', 1600, 1200, null, 1);

  p2 := tests.demo_add_post(mom, 'Sunday walk with your father. He insisted on the long way round.', null, interval '4 days');
  m := tests.demo_add_media(mom, p2, 'post', 'photo', 'p03', 1600, 1200, null, 0);

  p3 := tests.demo_add_post(dad, 'Fixed the fence. Finally.', null, interval '2 days');
  m := tests.demo_add_media(dad, p3, 'post', 'video', 'v1', 1280, 720, 8, 0);

  p4 := tests.demo_add_post(ana, 'Weekend in Point Reyes. Zero phone signal, ten out of ten.', 'Point Reyes National Seashore', interval '6 hours');
  m := tests.demo_add_media(ana, p4, 'post', 'photo', 'p05', 1600, 1200, null, 0);
  m := tests.demo_add_media(ana, p4, 'post', 'photo', 'p06', 1600, 1200, null, 1);
  m := tests.demo_add_media(ana, p4, 'post', 'photo', 'p07', 1600, 1200, null, 2);

  p5 := tests.demo_add_post(ana, 'Coffee and a book. Responses off because I am reading.', null, interval '3 days', false);
  m := tests.demo_add_media(ana, p5, 'post', 'photo', 'p08', 1600, 1200, null, 0);

  p6 := tests.demo_add_post(josh, 'Hike with the dogs. They slept the whole afternoon after.', 'Skyline Ridge', interval '2 days');
  m := tests.demo_add_media(josh, p6, 'post', 'photo', 'p09', 1600, 1200, null, 0);
  m := tests.demo_add_media(josh, p6, 'post', 'photo', 'p10', 1600, 1200, null, 1);

  p7 := tests.demo_add_post(josh, 'New bike day.', null, interval '8 days');
  m := tests.demo_add_media(josh, p7, 'post', 'photo', 'p11', 1600, 1200, null, 0);

  p8 := tests.demo_add_post(priya, 'Diwali prep has begun. Send help and more ghee.', null, interval '12 hours');
  m := tests.demo_add_media(priya, p8, 'post', 'photo', 'p12', 1600, 1200, null, 0);
  m := tests.demo_add_media(priya, p8, 'post', 'video', 'v2', 1280, 720, 8, 1);

  p9 := tests.demo_add_post(priya, 'Garden update: the squash has taken over.', null, interval '5 days');
  m := tests.demo_add_media(priya, p9, 'post', 'photo', 'p14', 1600, 1200, null, 0);

  p10 := tests.demo_add_post(ben, 'Lake trip. Water was freezing, went in anyway.', 'Lake Tahoe', interval '1 day');
  m := tests.demo_add_media(ben, p10, 'post', 'photo', 'p15', 1600, 1200, null, 0);
  m := tests.demo_add_media(ben, p10, 'post', 'photo', 'p16', 1600, 1200, null, 1);

  p11 := tests.demo_add_post(mom, 'Grandma''s apple pie recipe, finally written down.', null, interval '10 days');
  m := tests.demo_add_media(mom, p11, 'post', 'photo', 'p17', 1600, 1200, null, 0);

  p12 := tests.demo_add_post(sam, 'Nobody follows me, so nobody sees this.', null, interval '1 day');
  m := tests.demo_add_media(sam, p12, 'post', 'photo', 'p18', 1600, 1200, null, 0);

  -- Likes (Josh's hike gets "Mom and 3 others")
  call tests.demo_like(josh, p1, interval '20 hours');
  call tests.demo_like(josh, p4, interval '5 hours');
  call tests.demo_like(josh, p8, interval '11 hours');
  call tests.demo_like(mom, p6, interval '40 hours');
  call tests.demo_like(dad, p6, interval '38 hours');
  call tests.demo_like(ana, p6, interval '30 hours');
  call tests.demo_like(priya, p6, interval '26 hours');
  call tests.demo_like(mom, p7, interval '7 days');
  call tests.demo_like(ana, p7, interval '7 days');
  call tests.demo_like(priya, p9, interval '4 days');
  call tests.demo_like(ben, p9, interval '4 days');

  -- Stories (A3: own story first; one expired for the archive)
  m := tests.demo_add_media(mom, null, 'story', 'photo', 's-mom', 1600, 1200, null, 0);
  insert into public.stories (author_id, media_id, created_at, expires_at) values (mom, m, now() - interval '2 hours', now() + interval '22 hours') returning id into s_mom;
  m := tests.demo_add_media(ana, null, 'story', 'video', 's-ana', 1280, 720, 8, 0);
  insert into public.stories (author_id, media_id, location_name, created_at, expires_at) values (ana, m, 'Stinson Beach', now() - interval '5 hours', now() + interval '19 hours') returning id into s_ana;
  m := tests.demo_add_media(priya, null, 'story', 'photo', 's-priya', 1600, 1200, null, 0);
  insert into public.stories (author_id, media_id, created_at, expires_at) values (priya, m, now() - interval '8 hours', now() + interval '16 hours') returning id into s_priya;
  m := tests.demo_add_media(josh, null, 'story', 'photo', 's-josh', 1600, 1200, null, 0);
  insert into public.stories (author_id, media_id, created_at, expires_at) values (josh, m, now() - interval '1 hour', now() + interval '23 hours') returning id into s_josh;
  m := tests.demo_add_media(josh, null, 'story', 'photo', 's-josh-old', 1600, 1200, null, 0);
  insert into public.stories (author_id, media_id, created_at, expires_at) values (josh, m, now() - interval '30 hours', now() - interval '6 hours') returning id into s_josh_old;

  insert into public.story_views (story_id, viewer_id, viewed_at) values (s_mom, josh, now() - interval '90 minutes');
  insert into public.story_views (story_id, viewer_id, viewed_at) values (s_josh, mom, now() - interval '50 minutes');
  insert into public.story_views (story_id, viewer_id, viewed_at) values (s_josh, priya, now() - interval '40 minutes');

  -- Conversations (each started by a response, spec 7)
  insert into public.conversations (user_a, user_b, created_at, last_message_at)
  values (least(josh, mom), greatest(josh, mom), now() - interval '40 hours', now() - interval '39 hours') returning id into c_josh_mom;
  insert into public.messages (conversation_id, sender_id, kind, body, post_id, created_at) values
    (c_josh_mom, mom, 'post_response', 'Beautiful! Which trail was this?', p6, now() - interval '40 hours'),
    (c_josh_mom, josh, 'text', 'Skyline, the loop near the reservoir. You and Dad would like it.', null, now() - interval '39 hours 30 minutes'),
    (c_josh_mom, mom, 'text', 'Sunday then. I''ll bring sandwiches.', null, now() - interval '39 hours');
  insert into public.conversation_reads (conversation_id, user_id, last_read_at) values (c_josh_mom, josh, now() - interval '39 hours 20 minutes');
  insert into public.conversation_reads (conversation_id, user_id, last_read_at) values (c_josh_mom, mom, now() - interval '39 hours');

  insert into public.conversations (user_a, user_b, created_at, last_message_at)
  values (least(ana, josh), greatest(ana, josh), now() - interval '5 hours', now() - interval '4 hours') returning id into c_ana_josh;
  insert into public.messages (conversation_id, sender_id, kind, body, post_id, created_at) values
    (c_ana_josh, josh, 'post_response', 'This looks amazing. Where did you stay?', p4, now() - interval '5 hours'),
    (c_ana_josh, ana, 'text', 'A tiny cabin near Inverness. Come next time!', null, now() - interval '4 hours');
  insert into public.conversation_reads (conversation_id, user_id, last_read_at) values (c_ana_josh, ana, now() - interval '4 hours');

  insert into public.conversations (user_a, user_b, created_at, last_message_at)
  values (least(priya, josh), greatest(priya, josh), now() - interval '40 minutes', now() - interval '40 minutes') returning id into c_priya_josh;
  insert into public.messages (conversation_id, sender_id, kind, body, story_id, created_at) values
    (c_priya_josh, priya, 'story_reaction', '❤️', s_josh, now() - interval '40 minutes');
  insert into public.conversation_reads (conversation_id, user_id, last_read_at) values (c_priya_josh, priya, now() - interval '40 minutes');
end $$;
