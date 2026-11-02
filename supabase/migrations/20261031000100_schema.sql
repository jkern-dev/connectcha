-- Connectcha schema (implementation plan section 3.2).
--
-- Rules that this file sets up and later migrations rely on:
--   * Every table has row-level security enabled. With no policy a table is
--     unreadable and unwritable by clients, so a forgotten policy fails closed.
--   * Clients (roles anon and authenticated) get SELECT on a table only where a
--     later migration adds a SELECT policy, and never INSERT/UPDATE/DELETE.
--     All writes go through SECURITY DEFINER functions (plan 3.4).
--   * Helpers that must not be callable by clients live in schema `private`.
--   * There is no table for contacts, contact names, non-user numbers, matched
--     sets, follower counts or analytics. That absence is deliberate (plan 3.2).

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

-- Default privileges: nothing for clients unless granted explicitly. Supabase
-- cloud grants everything to anon/authenticated by default, so this makes local
-- and hosted behave the same. Each migration grants exactly what it means to.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;
-- Postgres also grants EXECUTE to PUBLIC on new functions by default; remove that too.
alter default privileges for role postgres in schema public revoke execute on functions from public;
alter default privileges for role postgres in schema private revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.request_source as enum ('contact', 'follow_back');
create type public.request_status as enum ('pending', 'approved', 'declined', 'cancelled');
create type public.media_kind as enum ('photo', 'video');
create type public.media_usage as enum ('post', 'story', 'avatar');
create type public.media_status as enum ('pending', 'ready');
create type public.message_kind as enum ('text', 'post_response', 'story_response', 'story_reaction');
create type public.activity_type as enum ('follow_request', 'request_approved', 'like');
create type public.push_type as enum ('follow_request', 'request_approved', 'message', 'bell_post', 'bell_story');

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  first_name text not null default '' check (char_length(first_name) <= 50),
  last_name text not null default '' check (char_length(last_name) <= 50),
  bio text not null default '' check (char_length(bio) <= 150),
  avatar_media_id uuid,
  -- SHA-256 hex of the E.164 number with its leading "+". Maintained only by
  -- the trigger on auth.users below. Never exposed through any view or function.
  phone_hash text unique,
  -- Set when the person has given first and last name. Only onboarded people
  -- can be matched from contacts.
  onboarded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.profiles is 'Base table. No client grants; read through profiles_minimal / profiles_full.';

-- ---------------------------------------------------------------------------
-- Follow graph
-- ---------------------------------------------------------------------------
create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index follows_followee_idx on public.follows (followee_id);

create table public.follow_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  source public.request_source not null,
  status public.request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (requester_id <> target_id)
);
create unique index follow_requests_one_pending_idx
  on public.follow_requests (requester_id, target_id) where status = 'pending';
create index follow_requests_target_idx on public.follow_requests (target_id, status);
create index follow_requests_requester_idx on public.follow_requests (requester_id, status);

-- ---------------------------------------------------------------------------
-- Posts, media, likes
-- ---------------------------------------------------------------------------
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  caption text not null default '' check (char_length(caption) <= 1000),
  location_name text check (char_length(location_name) <= 200),
  location_lat double precision,
  location_lng double precision,
  responses_enabled boolean not null default true,
  -- null until every media row is ready and publish_post has run.
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index posts_feed_idx on public.posts (published_at desc) where published_at is not null;
create index posts_author_idx on public.posts (author_id, published_at desc);

create table public.media (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  post_id uuid references public.posts (id) on delete cascade,
  usage public.media_usage not null,
  kind public.media_kind not null,
  -- Object keys are random UUIDs under media/{owner_id}/ in the private bucket.
  object_key text not null unique,
  thumb_key text unique,
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  duration_s numeric(6, 2) check (duration_s is null or (duration_s >= 0 and duration_s <= 60)),
  bytes bigint check (bytes is null or bytes >= 0),
  position integer not null default 0,
  status public.media_status not null default 'pending',
  created_at timestamptz not null default now(),
  check (usage <> 'post' or post_id is not null)
);
create index media_post_idx on public.media (post_id, position);
create index media_owner_idx on public.media (owner_id, created_at desc);

alter table public.profiles
  add constraint profiles_avatar_media_fk foreign key (avatar_media_id)
  references public.media (id) on delete set null;

create table public.likes (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Stories
-- ---------------------------------------------------------------------------
create table public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  media_id uuid not null unique references public.media (id) on delete cascade,
  location_name text check (char_length(location_name) <= 200),
  replies_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  -- Visibility policies compare this to now(); no expiry job is needed. The
  -- author's rows past expiry are the private archive.
  expires_at timestamptz not null default now() + interval '24 hours'
);
create index stories_author_idx on public.stories (author_id, created_at desc);
create index stories_expires_idx on public.stories (expires_at);

create table public.story_views (
  story_id uuid not null references public.stories (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

-- ---------------------------------------------------------------------------
-- Messaging
-- ---------------------------------------------------------------------------
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles (id) on delete cascade,
  user_b uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unique (user_a, user_b),
  check (user_a < user_b)
);
create index conversations_user_b_idx on public.conversations (user_b);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  kind public.message_kind not null default 'text',
  body text not null check (char_length(body) <= 2000),
  post_id uuid references public.posts (id) on delete set null,
  story_id uuid references public.stories (id) on delete set null,
  created_at timestamptz not null default now()
);
create index messages_conversation_idx on public.messages (conversation_id, created_at);

create table public.conversation_reads (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Feed marker, activity, bells, notifications
-- ---------------------------------------------------------------------------
create table public.feed_seen (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  seen_through timestamptz not null,
  updated_at timestamptz not null default now()
);

create table public.activity (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  type public.activity_type not null,
  post_id uuid references public.posts (id) on delete cascade,
  request_id uuid references public.follow_requests (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index activity_recipient_idx on public.activity (recipient_id, created_at desc);

create table public.bells (
  user_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, target_id)
);
create index bells_target_idx on public.bells (target_id);

create table public.notification_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  requests boolean not null default true,
  messages boolean not null default true,
  likes boolean not null default true,
  bells boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null check (platform in ('ios', 'ios_simulator')),
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.push_outbox (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  type public.push_type not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  attempts integer not null default 0
);
create index push_outbox_unsent_idx on public.push_outbox (created_at) where sent_at is null;

-- ---------------------------------------------------------------------------
-- Row-level security: on everywhere, no policies yet (deny all).
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.follows enable row level security;
alter table public.follow_requests enable row level security;
alter table public.posts enable row level security;
alter table public.media enable row level security;
alter table public.likes enable row level security;
alter table public.stories enable row level security;
alter table public.story_views enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.conversation_reads enable row level security;
alter table public.feed_seen enable row level security;
alter table public.activity enable row level security;
alter table public.bells enable row level security;
alter table public.notification_settings enable row level security;
alter table public.device_tokens enable row level security;
alter table public.push_outbox enable row level security;

-- Belt and braces on top of the default-privilege change above.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Visibility helpers (plan 3.1 rule 3). The single-argument public versions
-- take the viewer from auth.uid(), so calling them directly reveals only the
-- caller's own relationships. The two-argument versions are private.
-- ---------------------------------------------------------------------------
create function private.can_view_content(viewer uuid, author uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select viewer is not null and (
    viewer = author
    or exists (
      select 1 from public.follows f
      where f.follower_id = viewer and f.followee_id = author
    )
  );
$$;

create function public.can_view_content(author uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.can_view_content(auth.uid(), author);
$$;

-- Whether the viewer legitimately holds a relationship with `other` and may
-- therefore read their minimal profile (name and photo). This is what stops
-- profiles_minimal from being an enumerable directory of all users.
create function private.can_see_profile(viewer uuid, other uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select viewer is not null and (
    viewer = other
    or exists (
      select 1 from public.follows f
      where (f.follower_id = viewer and f.followee_id = other)
         or (f.follower_id = other and f.followee_id = viewer)
    )
    or exists (
      select 1 from public.follow_requests r
      where (r.requester_id = viewer and r.target_id = other)
         or (r.requester_id = other and r.target_id = viewer and r.status = 'pending')
         or (r.requester_id = other and r.target_id = viewer and r.status = 'approved')
    )
    or exists (
      select 1 from public.conversations c
      where (c.user_a = least(viewer, other) and c.user_b = greatest(viewer, other))
    )
  );
$$;

create function public.can_see_profile(other uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.can_see_profile(auth.uid(), other);
$$;

revoke execute on function private.can_view_content(uuid, uuid) from public, anon, authenticated;
revoke execute on function private.can_see_profile(uuid, uuid) from public, anon, authenticated;
grant execute on function public.can_view_content(uuid) to authenticated;
grant execute on function public.can_see_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Keep profiles in step with auth.users: create the row on sign-up and keep
-- phone_hash current if the number ever changes. The phone number itself
-- stays only in auth.users, which clients cannot read.
-- ---------------------------------------------------------------------------
create function private.handle_auth_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, phone_hash)
  values (
    new.id,
    case when new.phone is null or new.phone = '' then null
         else encode(extensions.digest('+' || new.phone, 'sha256'), 'hex') end
  )
  on conflict (id) do update set
    phone_hash = excluded.phone_hash,
    updated_at = now();
  return new;
end;
$$;
revoke execute on function private.handle_auth_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_auth_user();

create trigger on_auth_user_phone_changed
  after update of phone on auth.users
  for each row
  when (old.phone is distinct from new.phone)
  execute function private.handle_auth_user();

-- updated_at maintenance
create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
revoke execute on function private.touch_updated_at() from public, anon, authenticated;

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();
create trigger posts_touch before update on public.posts
  for each row execute function private.touch_updated_at();
