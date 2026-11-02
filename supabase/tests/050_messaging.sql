-- Messaging: responses are private to the pair (S12), conversations go
-- read-only when no follow remains (S13), previews for deleted posts and
-- expired stories (A2), poster settings.
begin;
select plan(31);
select tests.seed_fixture();

-- --- A response opens the pair's conversation and nobody else sees it (S12) ------
select tests.authenticate_as('ana');
select lives_ok($$ select public.respond_to_post(tests.fixture_post(), 'Lovely beach!') $$, 'ana responds to ben''s post');
select is(jsonb_array_length(public.get_inbox()), 1, 'ana''s inbox has the conversation');
select is((public.get_inbox() -> 0 -> 'last_message' ->> 'kind'), 'post_response', 'the message is a post response');
select is((public.get_inbox() -> 0 -> 'last_message' -> 'post' ->> 'id'), tests.fixture_post()::text, 'with a post preview');

select tests.authenticate_as('dave');
select is(jsonb_array_length(public.get_inbox()), 0, 'another follower (dave) has no conversation');
select is((select count(*) from public.messages), 0::bigint, 'dave sees no message rows');
select is((select count(*) from public.conversations), 0::bigint, 'dave sees no conversation rows');

select tests.authenticate_as('ben');
select is(jsonb_array_length(public.get_inbox()), 1, 'ben''s inbox has the conversation');
select is((public.get_inbox() -> 0 ->> 'unread')::boolean, true, 'it is unread for ben');
select is((public.get_unread_counts() ->> 'unread_conversations')::integer, 1, 'the inbox badge counts it');
select lives_ok($$ select public.mark_conversation_read((public.get_inbox() -> 0 ->> 'conversation_id')::uuid) $$, 'ben reads it');
select is((public.get_inbox() -> 0 ->> 'unread')::boolean, false, 'it is no longer unread');

-- The poster can reply even though he does not follow the responder (spec 7).
select lives_ok(
  $$ select public.send_message((public.get_inbox() -> 0 ->> 'conversation_id')::uuid, 'Thanks Ana!') $$,
  'a poster who does not follow the responder can reply');

-- A second response reuses the same conversation.
select tests.authenticate_as('ana');
select public.respond_to_post(tests.fixture_post(), 'Second thought');
select is(jsonb_array_length(public.get_inbox()), 1, 'each pair has exactly one conversation');
select is(jsonb_array_length(public.get_conversation((public.get_inbox() -> 0 ->> 'conversation_id')::uuid) -> 'messages'), 3,
  'the conversation holds all three messages');

-- Non-participants cannot send or read.
select tests.clear_auth();
create temporary table t_conv as select id from public.conversations limit 1;
grant select on t_conv to authenticated;
select tests.authenticate_as('dave');
select throws_ok(
  $$ select public.send_message((select id from t_conv), 'intruding') $$,
  'P0001', 'conversation_not_found', 'a non-participant cannot send into a conversation');
select throws_ok(
  $$ select public.get_conversation((select id from t_conv)) $$,
  'P0001', 'conversation_not_found', 'a non-participant cannot read a conversation');

-- --- S13: read-only when neither follows the other ----------------------------------
select tests.authenticate_as('ben');
select public.remove_follower(tests.user_id('ana'));
select is((public.get_conversation((select id from t_conv)) ->> 'can_send')::boolean, false,
  'with no follow in either direction, can_send is false');
select is(jsonb_array_length(public.get_conversation((select id from t_conv)) -> 'messages'), 3,
  'the conversation stays readable (S13)');
select throws_ok(
  $$ select public.send_message((select id from t_conv), 'one more') $$,
  'P0001', 'conversation_read_only', 'but new messages are refused (S13)');
select tests.authenticate_as('ana');
select throws_ok(
  $$ select public.send_message((select id from t_conv), 'hello?') $$,
  'P0001', 'conversation_read_only', 'for either side');
select throws_ok(
  $$ select public.respond_to_post(tests.fixture_post(), 'still there?') $$,
  'P0001', 'post_not_found', 'and the removed follower can no longer respond to the post');

-- Any follow restores messaging.
select tests.clear_auth();
insert into public.follows (follower_id, followee_id) values (tests.user_id('ben'), tests.user_id('ana'));
select tests.authenticate_as('ana');
select lives_ok($$ select public.send_message((select id from t_conv), 'back again') $$,
  'a follow in the other direction is enough to message again');

-- --- Poster settings and limits ------------------------------------------------------
select tests.clear_auth();
insert into public.follows (follower_id, followee_id) values (tests.user_id('ana'), tests.user_id('ben')) on conflict do nothing;
update public.posts set responses_enabled = false where id = tests.fixture_post();
select tests.authenticate_as('ana');
select throws_ok(
  $$ select public.respond_to_post(tests.fixture_post(), 'nope') $$,
  'P0001', 'responses_off', 'responses can be turned off per post');
select throws_ok(
  $$ select public.send_message((select id from t_conv), repeat('x', 2001)) $$,
  'P0001', 'message_too_long', 'messages are limited to 2,000 characters');
select throws_ok(
  $$ select public.send_message((select id from t_conv), '   ') $$,
  'P0001', 'message_empty', 'blank messages are refused');
select tests.authenticate_as('ben');
select throws_ok(
  $$ select public.respond_to_post(tests.fixture_post(), 'talking to myself') $$,
  'P0001', 'own_post', 'you cannot respond to your own post');

-- --- Story replies and previews (A2) ----------------------------------------------------
select tests.authenticate_as('ana');
select lives_ok($$ select public.respond_to_story(tests.fixture_story(), '❤️', true) $$, 'a quick reaction is sent as a message');
select is((public.get_inbox() -> 0 -> 'last_message' -> 'story' ->> 'id'), tests.fixture_story()::text, 'with a story preview');
select tests.clear_auth();
update public.stories set expires_at = now() - interval '1 minute' where id = tests.fixture_story();
select tests.authenticate_as('ana');
select is(jsonb_typeof(public.get_inbox() -> 0 -> 'last_message' -> 'story'), 'null', 'after expiry the preview is gone ("Story no longer available", A2)');

-- --- Deleted post preview -------------------------------------------------------------------
select tests.authenticate_as('ben');
select public.delete_post(tests.fixture_post());
select tests.authenticate_as('ana');
select is(
  (select count(*) from jsonb_array_elements(public.get_conversation((select id from t_conv)) -> 'messages') m
    where m ->> 'kind' = 'post_response' and jsonb_typeof(m -> 'post') = 'null'),
  2::bigint,
  'post responses to a deleted post keep their kind with no preview ("Post no longer available")');

select * from finish();
rollback;
