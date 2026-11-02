-- The privacy surface as a whole: non-persistence of submitted hashes,
-- push payloads without content or numbers, and an exact list of what a
-- signed-in client can call, so nothing is exposed by accident.
begin;
select plan(10);
select tests.seed_fixture();

-- --- Non-users' numbers are never kept (S8, plan 3.6) ---------------------------------
select tests.authenticate_as('ana');
select is(
  (select count(*) from public.match_contacts(array[tests.phone_hash('+15559990001'), tests.phone_hash('+15559990002')])),
  0::bigint,
  'unknown hashes match nobody');
select tests.clear_auth();
select is(tests.occurrences_anywhere(tests.phone_hash('+15559990001')), 0::bigint,
  'a submitted unknown hash is not stored in any table of public, auth or storage');

-- --- Push payloads carry ids and profile names only --------------------------------------
select tests.authenticate_as('stranger');
select public.send_follow_request(tests.user_id('ben'), tests.phone_hash('+15550001002'));
select tests.authenticate_as('ana');
select public.respond_to_post(tests.fixture_post(), 'A secret message body');
select tests.clear_auth();
select is((select count(*) from public.push_outbox where payload::text ilike '%secret message%'), 0::bigint,
  'message bodies are never placed in push payloads');
select is((select count(*) from public.push_outbox where payload::text ilike '%phone%' or payload::text like '%' || tests.phone_hash('+15550001002') || '%'), 0::bigint,
  'push payloads contain no phone numbers or hashes');
select is((select payload ->> 'actor_name' from public.push_outbox where type = 'follow_request' limit 1), 'Sam Stranger',
  'push payloads carry the actor''s profile name (the phone swaps in the saved name, G1)');
select is((select count(*) from public.push_outbox where type = 'follow_request' and recipient_id = tests.user_id('ben')), 1::bigint,
  'a follow request queues one push for the target');
select is((select count(*) from public.push_outbox where type = 'message' and recipient_id = tests.user_id('ben')), 1::bigint,
  'a response queues one push for the poster');

-- --- Exactly these functions are callable by signed-in clients ---------------------------
select set_eq(
  $$ select p.proname::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f'
        and has_function_privilege('authenticated', p.oid, 'EXECUTE') $$,
  array[
    -- policy helpers (viewer is always auth.uid())
    'can_view_content', 'can_see_profile', 'can_view_post', 'can_view_story',
    'is_post_author', 'is_story_author', 'is_conversation_participant',
    -- writes
    'update_profile', 'match_contacts',
    'send_follow_request', 'cancel_follow_request', 'approve_follow_request', 'decline_follow_request',
    'unfollow', 'remove_follower',
    'create_post', 'create_media', 'mark_media_ready', 'publish_post', 'update_post', 'delete_post',
    'like_post', 'unlike_post',
    'create_story', 'delete_story', 'mark_story_viewed',
    'respond_to_post', 'respond_to_story', 'send_message', 'mark_conversation_read',
    'mark_feed_seen', 'set_bell', 'update_notification_settings',
    'register_device_token', 'unregister_device_token',
    -- reads
    'get_me', 'get_feed', 'get_post', 'get_post_likers', 'get_profile', 'get_my_connections',
    'get_people', 'get_story_tray', 'get_story_viewers', 'get_my_story_archive',
    'get_inbox', 'get_conversation', 'get_message', 'get_unread_counts', 'get_activity'
  ],
  'the set of client-callable functions is exactly the documented API');

select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private', 'tests') and has_function_privilege('anon', p.oid, 'EXECUTE')
      and n.nspname <> 'tests'),
  0::bigint,
  'anon can call nothing');

-- Only match_contacts (echoing input), get_profile and send_follow_request (comparing a proof) may touch phone_hash.
select set_eq(
  $$ select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f'
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')
        and pg_get_functiondef(p.oid) ilike '%phone_hash%' $$,
  array['match_contacts', 'get_profile', 'send_follow_request'],
  'no other client-callable function reads phone_hash (these three compare a caller-supplied hash)');

select * from finish();
rollback;
