-- Schema invariants: every table locked down, phone numbers unreachable.
begin;
select plan(13);

-- All expected tables exist.
select has_table('public', t, 'table ' || t || ' exists')
from unnest(array[
  'profiles', 'follows', 'follow_requests', 'posts', 'media', 'likes', 'stories',
  'story_views', 'conversations', 'messages', 'conversation_reads', 'feed_seen',
  'activity', 'bells', 'notification_settings', 'device_tokens', 'push_outbox'
]) as t
limit 1;

-- Every table in public has row-level security enabled.
select is(
  (select count(*) from pg_tables where schemaname = 'public' and not rowsecurity),
  0::bigint,
  'every public table has RLS enabled'
);

-- Clients can never write a table directly: all writes go through functions.
select is(
  (select count(*) from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee in ('anon', 'authenticated')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')),
  0::bigint,
  'anon and authenticated have no write privilege on any public table'
);

-- anon can read nothing at all.
select is(
  (select count(*) from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'anon'),
  0::bigint,
  'anon has no privilege on any public table or view'
);

-- The base profiles table (which carries phone_hash) has no client grants.
select is(
  (select count(*) from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'profiles'
      and grantee in ('anon', 'authenticated')),
  0::bigint,
  'profiles base table is not readable by clients'
);

-- No client-readable relation in public exposes a column named phone_hash or phone.
select is(
  (select count(*)
     from information_schema.role_table_grants g
     join information_schema.columns c
       on c.table_schema = g.table_schema and c.table_name = g.table_name
    where g.table_schema = 'public'
      and g.grantee in ('anon', 'authenticated')
      and c.column_name in ('phone_hash', 'phone', 'phone_number')),
  0::bigint,
  'no client-readable relation exposes a phone or phone_hash column'
);

-- auth.users is unreadable by clients.
select is(
  (select count(*) from information_schema.role_table_grants
    where table_schema = 'auth' and table_name = 'users'
      and grantee in ('anon', 'authenticated')),
  0::bigint,
  'auth.users is not readable by clients'
);

-- The private schema is not usable by clients.
select ok(
  not has_schema_privilege('authenticated', 'private', 'USAGE')
  and not has_schema_privilege('anon', 'private', 'USAGE'),
  'private schema is not usable by clients'
);

-- Creating an auth user creates a profile with the expected phone hash.
select tests.create_user('schema_user', '15550009001');
select is(
  (select phone_hash from public.profiles where id = tests.user_id('schema_user')),
  tests.phone_hash('+15550009001'),
  'profiles.phone_hash is SHA-256 of the E.164 number with leading +'
);

-- Changing the phone changes the hash.
update auth.users set phone = '15550009002' where id = tests.user_id('schema_user');
select is(
  (select phone_hash from public.profiles where id = tests.user_id('schema_user')),
  tests.phone_hash('+15550009002'),
  'phone_hash follows a number change'
);

-- An authenticated client cannot select from the base profiles table.
select tests.authenticate_as('schema_user');
select throws_ok(
  $$ select phone_hash from public.profiles $$,
  '42501',
  null,
  'authenticated client is denied SELECT phone_hash FROM profiles'
);
select throws_ok(
  $$ select * from auth.users $$,
  '42501',
  null,
  'authenticated client is denied SELECT FROM auth.users'
);

-- The private two-argument helpers are not callable by clients.
select throws_ok(
  $$ select private.can_view_content(tests.user_id('schema_user'), tests.user_id('schema_user')) $$,
  '42501',
  null,
  'authenticated client cannot call private.can_view_content'
);

select * from finish();
rollback;
