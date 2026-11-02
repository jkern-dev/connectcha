-- Posts, media and likes: nobody sees posts without approval (S2, S5),
-- like visibility (S11), creation rules (spec 5.2).
begin;
select plan(43);
select tests.seed_fixture();

-- --- Visibility by relationship -------------------------------------------------
select tests.authenticate_as('ana');
select is((select count(*) from public.posts), 1::bigint, 'an approved follower sees the published post');
select is((select count(*) from public.media where post_id = tests.fixture_post()), 2::bigint, 'and its media rows');
select is(jsonb_array_length(public.get_feed() -> 'posts'), 1, 'the feed contains it');
select is((select count(*) from public.posts where id = tests.fixture_draft()), 0::bigint, 'the unpublished draft is hidden from followers');
select is((select count(*) from public.media where post_id = tests.fixture_draft()), 0::bigint, 'and so are its media rows');

select tests.authenticate_as('ben');
select is((select count(*) from public.posts), 2::bigint, 'the author sees the draft and the published post');

select tests.authenticate_as('pending');
select is((select count(*) from public.posts), 0::bigint, 'pending requester: no posts (S2)');
select is((select count(*) from public.media), 0::bigint, 'pending requester: no media');
select is(jsonb_array_length(public.get_feed() -> 'posts'), 0, 'pending requester: empty feed');
select throws_ok($$ select public.get_post(tests.fixture_post()) $$, 'P0001', 'post_not_found', 'pending requester: get_post refused');
select throws_ok($$ select public.like_post(tests.fixture_post()) $$, 'P0001', 'post_not_found', 'pending requester: cannot like');

select tests.authenticate_as('declined');
select is((select count(*) from public.posts), 0::bigint, 'declined requester: no posts (S2)');
select is((select count(*) from public.media), 0::bigint, 'declined requester: no media');

select tests.authenticate_as('removed');
select is((select count(*) from public.posts), 0::bigint, 'removed follower: no posts (S5)');
select is((select count(*) from public.media), 0::bigint, 'removed follower: no media');

select tests.authenticate_as('stranger');
select is((select count(*) from public.posts), 0::bigint, 'stranger: no posts');
select is((select count(*) from public.post_like_counts), 0::bigint, 'stranger: no like counts');

-- --- Creation rules ---------------------------------------------------------------
select tests.authenticate_as('ana');
select throws_ok(
  $$ select public.create_post('', null, null, null, true, '[]'::jsonb) $$,
  'P0001', 'media_count_invalid', 'a post needs at least one item');
select throws_ok(
  $$ select public.create_post('', null, null, null, true,
       (select jsonb_agg(jsonb_build_object('kind', 'photo')) from generate_series(1, 11))) $$,
  'P0001', 'media_count_invalid', 'a post has at most ten items');
select throws_ok(
  $$ select public.create_post('', null, null, null, true, '[{"kind":"video","duration_s":61}]'::jsonb) $$,
  'P0001', 'video_too_long', 'a 61-second video is refused');
select throws_ok(
  $$ select public.create_post(repeat('x', 1001), null, null, null, true, '[{"kind":"photo"}]'::jsonb) $$,
  'P0001', 'caption_too_long', 'captions are limited to 1,000 characters');

select tests.authenticate_as('ana');
create temporary table t_post as
  select public.create_post('Hello', 'Golden Gate Park', 37.77, -122.45, true,
    '[{"kind":"photo"},{"kind":"video","duration_s":59.5}]'::jsonb) as r;
select tests.clear_auth();
grant select on t_post to authenticated;
select is(jsonb_array_length((select r -> 'media' from t_post)), 2, 'create_post returns one descriptor per item');
select ok((select r -> 'media' -> 0 ->> 'object_key' from t_post) like 'media/' || tests.user_id('ana') || '/%.jpg',
  'object keys live under media/{owner}/');
select ok((select r -> 'media' -> 1 ->> 'object_key' from t_post) like '%.mp4', 'video keys end in .mp4');

select tests.authenticate_as('ana');
select throws_ok(
  $$ select public.publish_post((select (r ->> 'post_id')::uuid from t_post)) $$,
  'P0001', 'media_not_ready', 'a post cannot be published before its media is ready');
select tests.authenticate_as('ben');
select throws_ok(
  $$ select public.mark_media_ready((select (r -> 'media' -> 0 ->> 'id')::uuid from t_post), 2048, 1536) $$,
  'P0001', 'media_not_found', 'someone else cannot mark your media ready');
select throws_ok(
  $$ select public.publish_post((select (r ->> 'post_id')::uuid from t_post)) $$,
  'P0001', 'post_not_found', 'someone else cannot publish your post');

select tests.authenticate_as('ana');
select public.mark_media_ready((select (r -> 'media' -> 0 ->> 'id')::uuid from t_post), 2048, 1536, null, 350000);
select public.mark_media_ready((select (r -> 'media' -> 1 ->> 'id')::uuid from t_post), 1920, 1080, 59.5, 9000000);
select lives_ok(
  $$ select public.publish_post((select (r ->> 'post_id')::uuid from t_post)) $$,
  'publishing succeeds once every item is ready');

-- Ben does not follow Ana, so he must not see her new post.
select tests.authenticate_as('ben');
select is((select count(*) from public.posts where author_id = tests.user_id('ana')), 0::bigint,
  'the poster''s followers-only rule applies to the new post');

-- --- Likes (S11) -------------------------------------------------------------------
select tests.authenticate_as('ana');
select lives_ok($$ select public.like_post(tests.fixture_post()) $$, 'ana likes ben''s post');
select tests.authenticate_as('dave');
select lives_ok($$ select public.like_post(tests.fixture_post()) $$, 'dave likes it too');
select is((select like_count from public.post_like_counts where post_id = tests.fixture_post()), 2,
  'a viewer sees the count');
select is((select count(*) from public.likes where post_id = tests.fixture_post()), 1::bigint,
  'a viewer sees only their own like row');
select throws_ok($$ select public.get_post_likers(tests.fixture_post()) $$, 'P0001', 'post_not_found',
  'a viewer cannot list who liked');
select tests.authenticate_as('ben');
select is(jsonb_array_length(public.get_post_likers(tests.fixture_post())), 2, 'the poster sees who liked');
select is((select count(*) from public.activity where type = 'like'), 2::bigint, 'likes appear in the poster''s activity');
select tests.clear_auth();
select is((select count(*) from public.push_outbox where type::text like '%like%'), 0::bigint, 'likes never queue a push');
select tests.authenticate_as('dave');
select public.unlike_post(tests.fixture_post());
select is((select like_count from public.post_like_counts where post_id = tests.fixture_post()), 1, 'unlike lowers the count');

-- --- Edit and delete ----------------------------------------------------------------
select tests.authenticate_as('ana');
select throws_ok(
  $$ select public.update_post(tests.fixture_post(), 'hijack', null, null, null, true) $$,
  'P0001', 'post_not_found', 'only the author can edit');
select throws_ok(
  $$ select public.delete_post(tests.fixture_post()) $$,
  'P0001', 'post_not_found', 'only the author can delete');
select tests.authenticate_as('ben');
select public.update_post(tests.fixture_post(), 'Beach day, edited', 'Santa Cruz', 36.97, -122.03, false);
select is((select caption from public.posts where id = tests.fixture_post()), 'Beach day, edited', 'the author can edit the caption and location (A4)');
select lives_ok($$ select public.delete_post(tests.fixture_post()) $$, 'the author can delete');
select is((select count(*) from public.media where object_key like '%fx-photo%'), 0::bigint, 'deleting a post removes its media rows');

select * from finish();
rollback;
