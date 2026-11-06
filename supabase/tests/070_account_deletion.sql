-- Account deletion (D-34) and push token platforms (D-33).
begin;
select plan(13);
select tests.seed_fixture();

-- --- token platforms ------------------------------------------------------------
select tests.authenticate_as('ana');
select lives_ok($$ select public.register_device_token('token-prod-ana-0001', 'ios') $$, 'a production token registers');
select lives_ok($$ select public.register_device_token('token-sandbox-ana-0001', 'ios_sandbox') $$, 'a sandbox token registers');
select throws_ok($$ select public.register_device_token('token-android-ana-0001', 'android') $$, '23514',
  null, 'an unknown platform is refused');

-- --- set up something to delete --------------------------------------------------
select lives_ok($$ select public.respond_to_post(tests.fixture_post(), 'Lovely beach!') $$, 'ana writes back about ben''s post');
select lives_ok($$ select public.like_post(tests.fixture_post()) $$, 'ana finds it lovely');
select tests.authenticate_as('ben');
select is(jsonb_array_length(public.get_inbox()), 1, 'ben has the conversation with ana');

-- --- delete ---------------------------------------------------------------------
select tests.authenticate_as('ana');
select lives_ok($$ select public.delete_my_account() $$, 'ana deletes her account');

select tests.clear_auth();
select is((select count(*) from auth.users where id = tests.user_id('ana')), 0::bigint, 'the auth user is gone');
select is((select count(*) from public.profiles where id = tests.user_id('ana')), 0::bigint, 'the profile is gone');
select is((select count(*) from public.device_tokens where user_id = tests.user_id('ana')), 0::bigint, 'her device tokens are gone');
select is((select count(*) from public.follows where follower_id = tests.user_id('ana')), 0::bigint, 'her follows are gone');

-- --- what the other person keeps ---------------------------------------------------
select tests.authenticate_as('ben');
select is((select count(*) from public.posts where id = tests.fixture_post()), 1::bigint, 'ben''s post is untouched');
select is(jsonb_array_length(public.get_inbox()), 0, 'the conversation with the deleted person is gone from ben''s Letters');

select * from finish();
rollback;
