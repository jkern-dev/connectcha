-- Test and demo helpers. This is a seed file: it runs on `supabase db reset`
-- locally and in CI, and is never pushed to a hosted project.

create schema if not exists tests;
revoke all on schema tests from public;
revoke all on schema tests from anon, authenticated;

-- Deterministic user id from a label so demo data and tests can refer to
-- people by name.
create or replace function tests.user_id(label text)
returns uuid
language sql immutable
as $$
  select md5('connectcha:' || label)::uuid;
$$;

-- Creates an auth user with a verified US phone number (digits only, as
-- GoTrue stores them) and fills in the profile name. Idempotent.
create or replace function tests.create_user(
  label text,
  phone text,
  first_name text default null,
  last_name text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  uid uuid := tests.user_id(label);
begin
  insert into auth.users (
    id, instance_id, aud, role, phone, phone_confirmed_at,
    created_at, updated_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token,
    is_sso_user, is_anonymous
  ) values (
    uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', phone, now(),
    now(), now(), now(),
    '{"provider":"phone","providers":["phone"]}'::jsonb, '{}'::jsonb,
    '', '', '', '', '', '', '', '',
    false, false
  )
  on conflict (id) do nothing;

  if first_name is not null then
    update public.profiles
       set first_name = create_user.first_name,
           last_name = coalesce(create_user.last_name, ''),
           onboarded_at = coalesce(onboarded_at, now())
     where id = uid;
  end if;
  return uid;
end;
$$;

-- Run the rest of the transaction as this user, exactly as PostgREST would.
create or replace function tests.authenticate_as(label text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  uid uuid := tests.user_id(label);
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('role', 'anon', true);
end;
$$;

-- Back to the superuser for set-up steps between assertions.
create or replace function tests.clear_auth()
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('role', 'postgres', true);
end;
$$;

-- SHA-256 hex of an E.164 number, the same function the phone computes.
create or replace function tests.phone_hash(e164 text)
returns text
language sql immutable
as $$
  select encode(extensions.digest(e164, 'sha256'), 'hex');
$$;

-- Helpers must stay callable after authenticate_as switched the role.
grant usage on schema tests to authenticated, anon;

-- Standard fixture used by the access-rule tests (plan section 5):
--   ben       author of a published post (photo + video), a draft post, an
--             active story and an expired story
--   ana       approved follower of ben
--   dave      approved follower of ben (third party for privacy checks)
--   pending   has a pending request to ben
--   declined  had a request to ben that ben declined
--   removed   used to follow ben; ben removed them
--   stranger  no relationship with anyone
-- Ana follows Ben; Ben follows nobody; nobody has anyone else's number unless
-- a test passes the hash explicitly.
create or replace function tests.seed_fixture()
returns void
language plpgsql
set search_path = ''
as $$
declare
  ben uuid; ana uuid; dave uuid; pend uuid; decl uuid; remv uuid; strg uuid;
  post_id uuid; draft_id uuid; m1 uuid; m2 uuid; m3 uuid; m4 uuid; m5 uuid;
  story_id uuid; old_story_id uuid;
begin
  ben  := tests.create_user('ben',      '15550001002', 'Ben', 'Carter');
  ana  := tests.create_user('ana',      '15550001001', 'Ana', 'Silva');
  dave := tests.create_user('dave',     '15550001003', 'Dave', 'Moss');
  pend := tests.create_user('pending',  '15550001005', 'Pat', 'Pending');
  decl := tests.create_user('declined', '15550001006', 'Dee', 'Declined');
  remv := tests.create_user('removed',  '15550001007', 'Rae', 'Removed');
  strg := tests.create_user('stranger', '15550001004', 'Sam', 'Stranger');

  update public.profiles set bio = 'Ben''s bio' where id = ben;

  insert into public.follows (follower_id, followee_id) values (ana, ben), (dave, ben)
  on conflict do nothing;

  insert into public.follow_requests (requester_id, target_id, source, status, resolved_at) values
    (ana,  ben, 'contact', 'approved', now()),
    (dave, ben, 'contact', 'approved', now()),
    (pend, ben, 'contact', 'pending', null),
    (decl, ben, 'contact', 'declined', now()),
    (remv, ben, 'contact', 'approved', now());

  -- Published post with a photo and a video.
  insert into public.posts (author_id, caption, published_at) values (ben, 'Beach day', now() - interval '1 hour')
  returning id into post_id;
  insert into public.media (owner_id, post_id, usage, kind, object_key, thumb_key, width, height, position, status)
  values (ben, post_id, 'post', 'photo', 'media/' || ben || '/fx-photo.jpg', 'media/' || ben || '/fx-photo_thumb.jpg', 2048, 1536, 0, 'ready')
  returning id into m1;
  insert into public.media (owner_id, post_id, usage, kind, object_key, thumb_key, width, height, duration_s, position, status)
  values (ben, post_id, 'post', 'video', 'media/' || ben || '/fx-video.mp4', 'media/' || ben || '/fx-video_thumb.jpg', 1920, 1080, 12.5, 1, 'ready')
  returning id into m2;

  -- Draft post (media pending, not published).
  insert into public.posts (author_id, caption) values (ben, 'Draft') returning id into draft_id;
  insert into public.media (owner_id, post_id, usage, kind, object_key, thumb_key, position, status)
  values (ben, draft_id, 'post', 'photo', 'media/' || ben || '/fx-draft.jpg', 'media/' || ben || '/fx-draft_thumb.jpg', 0, 'pending')
  returning id into m3;

  -- Active story and an expired one.
  insert into public.media (owner_id, usage, kind, object_key, thumb_key, width, height, status)
  values (ben, 'story', 'photo', 'media/' || ben || '/fx-story.jpg', 'media/' || ben || '/fx-story_thumb.jpg', 1080, 1920, 'ready')
  returning id into m4;
  insert into public.stories (author_id, media_id) values (ben, m4) returning id into story_id;

  insert into public.media (owner_id, usage, kind, object_key, thumb_key, width, height, status)
  values (ben, 'story', 'photo', 'media/' || ben || '/fx-old-story.jpg', 'media/' || ben || '/fx-old-story_thumb.jpg', 1080, 1920, 'ready')
  returning id into m5;
  insert into public.stories (author_id, media_id, created_at, expires_at)
  values (ben, m5, now() - interval '30 hours', now() - interval '6 hours') returning id into old_story_id;
end;
$$;

-- Ids of fixture rows, looked up by name so tests stay readable.
create or replace function tests.fixture_post()
returns uuid language sql stable as $$
  select post_id from public.media where owner_id = tests.user_id('ben') and object_key like '%/fx-photo.jpg';
$$;
create or replace function tests.fixture_draft()
returns uuid language sql stable as $$
  select post_id from public.media where owner_id = tests.user_id('ben') and object_key like '%/fx-draft.jpg';
$$;
create or replace function tests.fixture_story()
returns uuid language sql stable as $$
  select id from public.stories where author_id = tests.user_id('ben') and expires_at > now();
$$;
create or replace function tests.fixture_expired_story()
returns uuid language sql stable as $$
  select id from public.stories where author_id = tests.user_id('ben') and expires_at <= now();
$$;

-- Counts rows in every table of public and auth whose text contains needle.
-- Used to prove that submitted hashes and names are never persisted.
create or replace function tests.occurrences_anywhere(needle text)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  r record;
  n bigint;
  total bigint := 0;
begin
  for r in
    select schemaname, tablename from pg_catalog.pg_tables
    where schemaname in ('public', 'auth', 'storage')
  loop
    execute format('select count(*) from %I.%I t where t::text like %L', r.schemaname, r.tablename, '%' || needle || '%')
      into n;
    total := total + n;
  end loop;
  return total;
end;
$$;

grant execute on all functions in schema tests to authenticated, anon;

-- Local push webhook target: the Edge Runtime as seen from inside the
-- database container. The secret matches supabase/functions/.env.
insert into private.settings (key, value) values
  ('push_webhook_url', 'http://host.docker.internal:54321/functions/v1/send-push'),
  ('push_webhook_secret', 'local-dev-push-secret')
on conflict (key) do update set value = excluded.value;
