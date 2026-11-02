-- Following: contact proof or follow-back only (S1, S3, S4), approval,
-- declines invisible to the sender (A1), crossing requests (G3),
-- remove follower (S5), own-edges-only follows (S16).
begin;
select plan(39);
select tests.seed_fixture();

-- --- S1: a request needs proof of the number -----------------------------------
select tests.authenticate_as('stranger');
select throws_ok(
  $$ select public.send_follow_request(tests.user_id('ben'), null) $$,
  'P0001', 'not_eligible',
  'no hash and no follow-back: refused');
select throws_ok(
  $$ select public.send_follow_request(tests.user_id('ben'), tests.phone_hash('+15550001099')) $$,
  'P0001', 'not_eligible',
  'wrong hash: refused');
select throws_ok(
  $$ select public.send_follow_request(tests.user_id('stranger'), tests.phone_hash('+15550001004')) $$,
  'P0001', 'cannot_follow_self',
  'cannot request yourself');
select lives_ok(
  $$ select public.send_follow_request(tests.user_id('ben'), tests.phone_hash('+15550001002')) $$,
  'correct hash: request created');
select is((select source::text from public.outgoing_requests where target_id = tests.user_id('ben')), 'contact',
  'the request is recorded as coming from contacts');
select throws_ok(
  $$ select public.send_follow_request(tests.user_id('ben'), tests.phone_hash('+15550001002')) $$,
  'P0001', 'request_pending',
  'a second request while one is outstanding is refused');

select tests.authenticate_as('ben');
select is((select count(*) from public.incoming_requests where requester_id = tests.user_id('stranger')), 1::bigint,
  'ben sees the incoming request');
select is((select count(*) from public.activity where type = 'follow_request' and actor_id = tests.user_id('stranger')), 1::bigint,
  'ben has an activity item for it');

-- --- S3: follow-back needs an active follow from the target --------------------
select tests.authenticate_as('ben');
select lives_ok(
  $$ select public.send_follow_request(tests.user_id('ana'), null) $$,
  'ben can request ana without her number because she follows him (follow-back)');
select is((select source::text from public.outgoing_requests where target_id = tests.user_id('ana')), 'follow_back',
  'the request is marked as a follow-back');
select tests.authenticate_as('ana');
select is((select count(*) from public.posts where author_id = tests.user_id('ben')), 1::bigint,
  'ana still sees ben''s post while his follow-back request is pending');
select tests.authenticate_as('ben');
select is((select count(*) from public.posts where author_id = tests.user_id('ana')), 0::bigint,
  'ben sees nothing of ana''s until she approves (S3)');

select throws_ok(
  $$ select public.send_follow_request(tests.user_id('pending'), null) $$,
  'P0001', 'not_eligible',
  'no follow-back while the other person''s request is only pending');
select throws_ok(
  $$ select public.send_follow_request(tests.user_id('declined'), null) $$,
  'P0001', 'not_eligible',
  'no follow-back after declining');

-- --- S4: follow-back right ends when the follow ends ----------------------------
select tests.authenticate_as('ben');
select lives_ok($$ select public.cancel_follow_request(id) from public.outgoing_requests where target_id = tests.user_id('ana') $$,
  'ben cancels his follow-back request');
select tests.authenticate_as('ana');
select lives_ok($$ select public.unfollow(tests.user_id('ben')) $$, 'ana unfollows ben');
select tests.authenticate_as('ben');
select throws_ok(
  $$ select public.send_follow_request(tests.user_id('ana'), null) $$,
  'P0001', 'not_eligible',
  'after ana unfollows, ben cannot follow back (S4)');
select lives_ok(
  $$ select public.send_follow_request(tests.user_id('ana'), tests.phone_hash('+15550001001')) $$,
  'but he can request her if he has her number');

-- --- Approval ----------------------------------------------------------------------
select tests.clear_auth();
create temporary table t_req as select id from public.follow_requests
  where requester_id = tests.user_id('stranger') and target_id = tests.user_id('ben') and status = 'pending';
grant select on t_req to authenticated;
select tests.authenticate_as('ana');
select throws_ok(
  $$ select public.approve_follow_request((select id from t_req)) $$,
  'P0001', 'request_not_found',
  'only the target can approve (ana cannot approve a request addressed to ben)');

select tests.authenticate_as('ben');
select is(
  (select (public.approve_follow_request(id) ->> 'follow_back_available')::boolean
     from public.incoming_requests where requester_id = tests.user_id('stranger')),
  true,
  'approving returns that a follow-back is now available');
select is((select count(*) from public.follows where follower_id = tests.user_id('stranger') and followee_id = tests.user_id('ben')), 1::bigint,
  'approval creates the follow');
select is((select count(*) from public.activity where type = 'follow_request' and actor_id = tests.user_id('stranger')), 0::bigint,
  'the request item leaves the approver''s activity');
select tests.authenticate_as('stranger');
select is((select count(*) from public.activity where type = 'request_approved' and actor_id = tests.user_id('ben')), 1::bigint,
  'the requester gets an approval item');
select is((select count(*) from public.posts where author_id = tests.user_id('ben')), 1::bigint,
  'the approved follower now sees the post');

-- Approve, then follow back; follow_back_available is false when already following.
select tests.authenticate_as('ben');
select lives_ok($$ select public.send_follow_request(tests.user_id('stranger'), null) $$,
  'ben follows back the newly approved follower');
select tests.authenticate_as('stranger');
select is(
  (select (public.approve_follow_request(id) ->> 'follow_back_available')::boolean
     from public.incoming_requests where requester_id = tests.user_id('ben')),
  false,
  'no follow-back offer when the approver already follows the requester');

-- --- A1: declines are invisible to the sender ----------------------------------------
select tests.authenticate_as('declined');
select is((select count(*) from public.outgoing_requests where target_id = tests.user_id('ben')), 1::bigint,
  'a declined request still shows as outstanding to its sender');
select throws_ok(
  $$ select public.send_follow_request(tests.user_id('ben'), tests.phone_hash('+15550001002')) $$,
  'P0001', 'request_pending',
  'the sender cannot stack a new request on a declined one');
select lives_ok(
  $$ select public.cancel_follow_request(id) from public.outgoing_requests where target_id = tests.user_id('ben') $$,
  'the sender can cancel it');
select lives_ok(
  $$ select public.send_follow_request(tests.user_id('ben'), tests.phone_hash('+15550001002')) $$,
  'and send a new one');
select tests.authenticate_as('ben');
select is((select count(*) from public.incoming_requests where requester_id = tests.user_id('declined')), 1::bigint,
  'ben sees the fresh request');
select lives_ok(
  $$ select public.decline_follow_request(id) from public.incoming_requests where requester_id = tests.user_id('declined') $$,
  'ben declines again');
select is((select count(*) from public.incoming_requests where requester_id = tests.user_id('declined')), 0::bigint,
  'declined requests leave ben''s incoming list');

-- --- G3: crossing requests stay independent --------------------------------------------
select tests.clear_auth();
select tests.create_user('cross_a', '15550001201', 'Cara', 'A');
select tests.create_user('cross_b', '15550001202', 'Cole', 'B');
select tests.authenticate_as('cross_a');
select public.send_follow_request(tests.user_id('cross_b'), tests.phone_hash('+15550001202'));
select tests.authenticate_as('cross_b');
select public.send_follow_request(tests.user_id('cross_a'), tests.phone_hash('+15550001201'));
select public.approve_follow_request(id) from public.incoming_requests where requester_id = tests.user_id('cross_a');
select is((select count(*) from public.follows where follower_id = tests.user_id('cross_b')), 0::bigint,
  'approving one crossing request does not approve the other');

-- --- S5: remove follower ------------------------------------------------------------------
select tests.authenticate_as('ben');
select lives_ok($$ select public.remove_follower(tests.user_id('dave')) $$, 'ben removes dave');
select tests.authenticate_as('dave');
select is((select count(*) from public.posts where author_id = tests.user_id('ben')), 0::bigint,
  'the removed follower loses access immediately (S5)');
select is((select count(*) from public.activity), 0::bigint,
  'the removed follower gets no activity item');
select tests.clear_auth();
select is((select count(*) from public.push_outbox where recipient_id = tests.user_id('dave')), 0::bigint,
  'the removed follower gets no push');

-- --- S16: you only ever see your own edges ----------------------------------------------
select tests.authenticate_as('pending');
select is((select count(*) from public.follows), 0::bigint,
  'a non-connected user sees no follow rows at all');

select * from finish();
rollback;
