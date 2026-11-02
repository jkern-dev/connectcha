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
