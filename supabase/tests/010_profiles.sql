-- Profiles: names reachable only through a relationship (D-05), bio only with
-- approval, phone data never exposed, onboarding, contact matching.
begin;
select plan(27);
select tests.seed_fixture();

-- --- profiles_minimal is not a directory ----------------------------------
select tests.authenticate_as('stranger');
select is((select count(*) from public.profiles_minimal), 1::bigint,
  'a stranger sees only their own row in profiles_minimal');

select tests.authenticate_as('ana');
select set_eq(
  $$ select id from public.profiles_minimal $$,
  array[tests.user_id('ana'), tests.user_id('ben')],
  'ana (follows ben) sees herself and ben only');

select tests.authenticate_as('ben');
select set_eq(
  $$ select id from public.profiles_minimal $$,
  array[tests.user_id('ben'), tests.user_id('ana'), tests.user_id('dave'), tests.user_id('pending'), tests.user_id('removed')],
  'ben sees his followers, pending requesters and past approvals, not the declined requester or strangers');

select tests.authenticate_as('declined');
select set_eq(
  $$ select id from public.profiles_minimal $$,
  array[tests.user_id('declined'), tests.user_id('ben')],
  'a declined requester still sees the person they requested (their request looks pending, A1)');

-- --- bio needs approval ------------------------------------------------------
select tests.authenticate_as('ana');
select is((select bio from public.profiles_full where id = tests.user_id('ben')), 'Ben''s bio',
  'an approved follower can read the bio');
select tests.authenticate_as('pending');
select is((select count(*) from public.profiles_full where id = tests.user_id('ben')), 0::bigint,
  'a pending requester cannot read the bio');
select tests.authenticate_as('removed');
select is((select count(*) from public.profiles_full where id = tests.user_id('ben')), 0::bigint,
  'a removed follower cannot read the bio');

-- --- no phone data in any client-facing shape --------------------------------
select tests.authenticate_as('ana');
select ok(public.get_profile(tests.user_id('ben'))::text !~* 'phone',
  'get_profile output never mentions a phone or hash');
select ok(public.get_me()::text !~* 'phone',
  'get_me output never mentions a phone or hash');
select hasnt_column('public', 'profiles_minimal', 'phone_hash', 'profiles_minimal has no phone_hash column');
select hasnt_column('public', 'profiles_full', 'phone_hash', 'profiles_full has no phone_hash column');

-- --- get_profile access ---------------------------------------------------------
select tests.authenticate_as('stranger');
select throws_ok(
  $$ select public.get_profile(tests.user_id('ben')) $$,
  'P0001', 'profile_not_found',
  'a stranger cannot open a profile by id');
select is(
  (public.get_profile(tests.user_id('ben'), tests.phone_hash('+15550001002')) -> 'profile' ->> 'first_name'),
  'Ben',
  'a stranger who proves they hold the number gets the minimal profile');
select is(
  (public.get_profile(tests.user_id('ben'), tests.phone_hash('+15550001002')) ->> 'can_view')::boolean,
  false,
  'holding the number does not grant content access');
select is(
  (public.get_profile(tests.user_id('ben'), tests.phone_hash('+15550001002')) -> 'posts'),
  '[]'::jsonb,
  'the minimal profile carries no posts');

select tests.authenticate_as('pending');
select is((public.get_profile(tests.user_id('ben')) ->> 'can_view')::boolean, false,
  'a pending requester gets only the minimal profile (S2)');
select is((public.get_profile(tests.user_id('ben')) -> 'relationship' ->> 'outgoing_request_id') is not null, true,
  'a pending requester sees that their request is outstanding');

select tests.authenticate_as('ana');
select is((public.get_profile(tests.user_id('ben')) ->> 'can_view')::boolean, true,
  'an approved follower gets the full profile');
select ok(public.get_profile(tests.user_id('ben')) ? 'follower_count' = false
       and public.get_profile(tests.user_id('ben')) ? 'following_count' = false,
  'another person''s profile carries no follower or following counts (S16)');

-- --- onboarding -----------------------------------------------------------------
select tests.clear_auth();
select tests.create_user('newbie', '15550001099');
select tests.authenticate_as('newbie');
select is((public.get_me() ->> 'onboarded')::boolean, false, 'a fresh sign-up is not onboarded');
select is((public.get_me() -> 'notification_settings' ->> 'messages')::boolean, true,
  'notification settings read as on before the row exists');
select throws_ok(
  $$ select public.update_profile('  ', 'Kern') $$,
  'P0001', 'name_required',
  'first and last name are both required');
select lives_ok(
  $$ select public.update_profile('Nia', 'Newbie', null, null) $$,
  'saving a name completes onboarding');
select is((public.get_me() ->> 'onboarded')::boolean, true, 'onboarded after saving a name');
select is((public.get_me() -> 'notification_settings' ->> 'requests')::boolean, true,
  'notification settings default to on');

-- --- match_contacts -------------------------------------------------------------
select tests.authenticate_as('stranger');
select set_eq(
  $$ select user_id from public.match_contacts(array[
       tests.phone_hash('+15550001002'),   -- ben
       tests.phone_hash('+15550001004'),   -- stranger themself
       tests.phone_hash('+15550009999')    -- nobody
     ]) $$,
  array[tests.user_id('ben')],
  'match_contacts returns matches for other onboarded people only');
select throws_ok(
  $$ select * from public.match_contacts(array_fill('x'::text, array[501])) $$,
  'P0001', 'too_many_hashes',
  'match_contacts refuses more than 500 hashes per call');

select * from finish();
rollback;
