-- Stories: 24-hour visibility, private archive (S14), approval required (S2),
-- viewer list only for the author.
begin;
select plan(24);
select tests.seed_fixture();

select tests.authenticate_as('ana');
select is((select count(*) from public.stories), 1::bigint, 'a follower sees the active story and not the expired one');
select is(jsonb_array_length(public.get_story_tray()), 1, 'the tray has one group');
select is((public.get_story_tray() -> 0 -> 'author' ->> 'first_name'), 'Ben', 'the group is ben''s');
select is((public.get_story_tray() -> 0 ->> 'all_seen')::boolean, false, 'it is unseen');
select is((select count(*) from public.media where id = (select media_id from public.stories where id = tests.fixture_story())), 1::bigint,
  'the story media row is visible to a follower');

select tests.authenticate_as('pending');
select is((select count(*) from public.stories), 0::bigint, 'a pending requester sees no stories (S2)');
select is(jsonb_array_length(public.get_story_tray()), 0, 'and an empty tray');
select is((select count(*) from public.media where usage = 'story'), 0::bigint, 'and no story media');
select throws_ok($$ select public.mark_story_viewed(tests.fixture_story()) $$, 'P0001', 'story_not_found',
  'a pending requester cannot mark a story viewed');

select tests.authenticate_as('stranger');
select is((select count(*) from public.stories), 0::bigint, 'a stranger sees no stories');

-- --- Viewing -------------------------------------------------------------------
select tests.authenticate_as('ana');
select lives_ok($$ select public.mark_story_viewed(tests.fixture_story()) $$, 'a follower can mark a story viewed');
select is((public.get_story_tray() -> 0 ->> 'all_seen')::boolean, true, 'the tray now shows it as seen');
select throws_ok($$ select public.get_story_viewers(tests.fixture_story()) $$, 'P0001', 'story_not_found',
  'a viewer cannot see who else viewed');
select is((select count(*) from public.story_views), 1::bigint, 'a viewer sees only their own view row');
select tests.authenticate_as('dave');
select is((select count(*) from public.story_views), 0::bigint, 'another follower sees no view rows');
select tests.authenticate_as('ben');
select is(jsonb_array_length(public.get_story_viewers(tests.fixture_story())), 1, 'the author sees the viewer list');
select is((public.get_story_viewers(tests.fixture_story()) -> 0 -> 'viewer' ->> 'first_name'), 'Ana', 'and it names ana');

-- --- Archive (S14) ---------------------------------------------------------------
select tests.authenticate_as('ben');
select is((select count(*) from public.stories), 2::bigint, 'the author sees active and expired stories');
select is(jsonb_array_length(public.get_my_story_archive()), 2, 'the archive lists both');
select is(jsonb_array_length(public.get_story_tray()), 1, 'the author''s own tray shows only the active story');

-- Expire the active story and check it disappears for followers but stays for the author.
select tests.clear_auth();
update public.stories set expires_at = now() - interval '1 minute' where id = tests.fixture_story();
select tests.authenticate_as('ana');
select is((select count(*) from public.stories), 0::bigint, 'after 24 hours a follower no longer sees the story (S14)');
select is((select count(*) from public.media where usage = 'story'), 0::bigint, 'nor its media');
select tests.authenticate_as('ben');
select is(jsonb_array_length(public.get_my_story_archive()), 2, 'the author''s archive still has it (S14)');

-- --- Creation rules -------------------------------------------------------------------
select tests.authenticate_as('ana');
select throws_ok(
  $$ select public.create_story((select (public.create_media('story', 'photo') ->> 'id')::uuid)) $$,
  'P0001', 'media_not_ready', 'a story needs media that finished uploading');

select * from finish();
rollback;
