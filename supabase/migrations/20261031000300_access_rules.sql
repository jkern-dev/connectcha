-- Access rules (plan 3.3), views, and the write functions (plan 3.4).
--
-- Conventions:
--   * Clients get SELECT only where a policy exists below. No client ever gets
--     INSERT/UPDATE/DELETE: every write is a SECURITY DEFINER function that
--     derives the caller from auth.uid() and raises on any rule violation.
--   * Errors raised to clients use errcode P0001 with a short snake_case
--     message the app maps to plain-language copy (see private.fail).
--   * Helpers callable from policies are one-argument public functions that
--     use auth.uid(); nothing callable by a client takes a viewer id.

-- ---------------------------------------------------------------------------
-- Error helper
-- ---------------------------------------------------------------------------
create function private.fail(code text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using message = code, errcode = 'P0001';
end;
$$;
revoke execute on function private.fail(text) from public, anon, authenticated;

create function private.require_user()
returns uuid
language plpgsql stable
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    perform private.fail('not_signed_in');
  end if;
  return uid;
end;
$$;
revoke execute on function private.require_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Policy helpers (public, single-argument, viewer = auth.uid())
-- ---------------------------------------------------------------------------
create function public.can_view_post(p_post_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.posts p
    where p.id = p_post_id
      and (p.author_id = auth.uid()
           or (p.published_at is not null and private.can_view_content(auth.uid(), p.author_id)))
  );
$$;

create function public.can_view_story(p_story_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.stories s
    where s.id = p_story_id
      and (s.author_id = auth.uid()
           or (s.expires_at > now() and private.can_view_content(auth.uid(), s.author_id)))
  );
$$;

create function public.is_post_author(p_post_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.posts p where p.id = p_post_id and p.author_id = auth.uid());
$$;

create function public.is_story_author(p_story_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.stories s where s.id = p_story_id and s.author_id = auth.uid());
$$;

create function public.is_conversation_participant(p_conversation_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id and (c.user_a = auth.uid() or c.user_b = auth.uid())
  );
$$;

grant execute on function public.can_view_post(uuid), public.can_view_story(uuid),
  public.is_post_author(uuid), public.is_story_author(uuid),
  public.is_conversation_participant(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Views over profiles. The base table has no client grants, so phone_hash is
-- unreachable. Minimal: name and photo, only for people you hold a
-- relationship with (D-05). Full: adds bio, only for people whose content you
-- may view.
-- ---------------------------------------------------------------------------
create view public.profiles_minimal
with (security_invoker = false) as
  select p.id, p.first_name, p.last_name, p.avatar_media_id
  from public.profiles p
  where p.onboarded_at is not null
    and public.can_see_profile(p.id);

create view public.profiles_full
with (security_invoker = false) as
  select p.id, p.first_name, p.last_name, p.avatar_media_id, p.bio
  from public.profiles p
  where p.onboarded_at is not null
    and public.can_view_content(p.id);

-- Requests as the two sides see them. Outgoing rows never carry a status: a
-- declined request looks exactly like a pending one to its sender (A1).
create view public.outgoing_requests
with (security_invoker = false) as
  select r.id, r.target_id, r.source, r.created_at
  from public.follow_requests r
  where r.requester_id = auth.uid()
    and r.status in ('pending', 'declined');

create view public.incoming_requests
with (security_invoker = false) as
  select r.id, r.requester_id, r.source, r.created_at
  from public.follow_requests r
  where r.target_id = auth.uid()
    and r.status = 'pending';

-- Like counts for posts you can see. Who liked is only in the likes table,
-- which the poster alone can read.
create view public.post_like_counts
with (security_invoker = false) as
  select l.post_id, count(*)::integer as like_count
  from public.likes l
  where public.can_view_post(l.post_id)
  group by l.post_id;

grant select on public.profiles_minimal, public.profiles_full,
  public.outgoing_requests, public.incoming_requests, public.post_like_counts
  to authenticated;

-- ---------------------------------------------------------------------------
-- SELECT policies (plan 3.3). Tables not listed stay unreadable
-- (profiles base table, follow_requests base table, push_outbox).
-- ---------------------------------------------------------------------------
create policy follows_select on public.follows for select to authenticated
  using (follower_id = auth.uid() or followee_id = auth.uid());

create policy posts_select on public.posts for select to authenticated
  using (author_id = auth.uid()
         or (published_at is not null and public.can_view_content(author_id)));

create policy media_select on public.media for select to authenticated
  using (
    owner_id = auth.uid()
    or usage = 'avatar'
    or (usage = 'post' and public.can_view_post(post_id))
    or (usage = 'story' and exists (
          select 1 from public.stories s where s.media_id = media.id and public.can_view_story(s.id)))
  );

create policy likes_select on public.likes for select to authenticated
  using (user_id = auth.uid() or public.is_post_author(post_id));

create policy stories_select on public.stories for select to authenticated
  using (author_id = auth.uid()
         or (expires_at > now() and public.can_view_content(author_id)));

create policy story_views_select on public.story_views for select to authenticated
  using (viewer_id = auth.uid() or public.is_story_author(story_id));

create policy conversations_select on public.conversations for select to authenticated
  using (user_a = auth.uid() or user_b = auth.uid());

create policy messages_select on public.messages for select to authenticated
  using (public.is_conversation_participant(conversation_id));

create policy conversation_reads_select on public.conversation_reads for select to authenticated
  using (user_id = auth.uid());

create policy feed_seen_select on public.feed_seen for select to authenticated
  using (user_id = auth.uid());

create policy activity_select on public.activity for select to authenticated
  using (recipient_id = auth.uid());

create policy bells_select on public.bells for select to authenticated
  using (user_id = auth.uid());

create policy notification_settings_select on public.notification_settings for select to authenticated
  using (user_id = auth.uid());

create policy device_tokens_select on public.device_tokens for select to authenticated
  using (user_id = auth.uid());

grant select on public.follows, public.posts, public.media, public.likes, public.stories,
  public.story_views, public.conversations, public.messages, public.conversation_reads,
  public.feed_seen, public.activity, public.bells, public.notification_settings,
  public.device_tokens to authenticated;

-- Realtime for messaging. Row-level security applies to these change feeds.
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.conversations;

-- ---------------------------------------------------------------------------
-- Push and activity helpers (private)
-- ---------------------------------------------------------------------------
create function private.profile_name(p_user uuid)
returns text
language sql stable
set search_path = ''
as $$
  select trim(p.first_name || ' ' || p.last_name) from public.profiles p where p.id = p_user;
$$;
revoke execute on function private.profile_name(uuid) from public, anon, authenticated;

-- Queues a push. The payload carries only ids, the actor's profile name and the
-- notification type. Never message bodies, captions, numbers or hashes.
create function private.enqueue_push(p_recipient uuid, p_type public.push_type, p_actor uuid, p_extra jsonb default '{}'::jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_recipient = p_actor then
    return;
  end if;
  insert into public.push_outbox (recipient_id, type, payload)
  values (
    p_recipient,
    p_type,
    jsonb_build_object(
      'type', p_type,
      'actor_id', p_actor,
      'actor_name', private.profile_name(p_actor)
    ) || coalesce(p_extra, '{}'::jsonb)
  );
end;
$$;
revoke execute on function private.enqueue_push(uuid, public.push_type, uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Profile
-- ---------------------------------------------------------------------------
create function public.update_profile(
  p_first_name text,
  p_last_name text,
  p_bio text default null,
  p_avatar_media_id uuid default null,
  p_clear_avatar boolean default false
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  fn text := nullif(trim(p_first_name), '');
  ln text := nullif(trim(p_last_name), '');
begin
  if fn is null or ln is null then
    perform private.fail('name_required');
  end if;
  if p_avatar_media_id is not null and not exists (
    select 1 from public.media m
    where m.id = p_avatar_media_id and m.owner_id = uid and m.usage = 'avatar'
  ) then
    perform private.fail('invalid_avatar');
  end if;

  update public.profiles
     set first_name = fn,
         last_name = ln,
         bio = coalesce(nullif(trim(p_bio), ''), case when p_bio is null then bio else '' end),
         avatar_media_id = case
           when p_clear_avatar then null
           when p_avatar_media_id is not null then p_avatar_media_id
           else avatar_media_id end,
         onboarded_at = coalesce(onboarded_at, now())
   where id = uid;

  insert into public.notification_settings (user_id) values (uid)
  on conflict (user_id) do nothing;
end;
$$;

-- Own profile, including the onboarding state and private counts (spec 8.2).
create function public.get_me()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'first_name', p.first_name,
    'last_name', p.last_name,
    'bio', p.bio,
    'avatar_media_id', p.avatar_media_id,
    'onboarded', p.onboarded_at is not null,
    'follower_count', (select count(*) from public.follows f where f.followee_id = p.id),
    'following_count', (select count(*) from public.follows f where f.follower_id = p.id),
    'pending_request_count', (select count(*) from public.follow_requests r where r.target_id = p.id and r.status = 'pending'),
    'notification_settings', coalesce((
      select jsonb_build_object('requests', n.requests, 'messages', n.messages, 'likes', n.likes, 'bells', n.bells)
      from public.notification_settings n where n.user_id = p.id),
      '{"requests":true,"messages":true,"likes":true,"bells":true}'::jsonb)
  )
  from public.profiles p
  where p.id = private.require_user();
$$;

-- ---------------------------------------------------------------------------
-- Contact matching (plan 3.4). Pure read. Returns only hashes the caller sent,
-- and only for people who finished onboarding. Nothing is written or logged.
-- ---------------------------------------------------------------------------
create function public.match_contacts(p_hashes text[])
returns table (hash text, user_id uuid, first_name text, last_name text, avatar_media_id uuid)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if p_hashes is null then
    return;
  end if;
  if cardinality(p_hashes) > 500 then
    perform private.fail('too_many_hashes');
  end if;
  return query
    select p.phone_hash, p.id, p.first_name, p.last_name, p.avatar_media_id
    from public.profiles p
    where p.phone_hash = any (p_hashes)
      and p.onboarded_at is not null
      and p.id <> uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Follow requests
-- ---------------------------------------------------------------------------
create function public.send_follow_request(p_target_id uuid, p_target_phone_hash text default null)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  target public.profiles%rowtype;
  by_contact boolean;
  by_follow_back boolean;
  new_id uuid;
begin
  if p_target_id = uid then
    perform private.fail('cannot_follow_self');
  end if;

  select * into target from public.profiles where id = p_target_id and onboarded_at is not null;
  if not found then
    perform private.fail('not_eligible');
  end if;

  if exists (select 1 from public.follows f where f.follower_id = uid and f.followee_id = p_target_id) then
    perform private.fail('already_following');
  end if;

  -- A declined request still looks pending to its sender (A1), so it blocks a
  -- duplicate the same way. The sender can cancel it and send a new one.
  if exists (select 1 from public.follow_requests r
              where r.requester_id = uid and r.target_id = p_target_id
                and r.status in ('pending', 'declined')) then
    perform private.fail('request_pending');
  end if;

  -- Eligibility (spec 3.3): proof of having the number, or the target follows
  -- the caller (follow-back).
  by_contact := p_target_phone_hash is not null and target.phone_hash = p_target_phone_hash;
  by_follow_back := exists (select 1 from public.follows f where f.follower_id = p_target_id and f.followee_id = uid);

  if not by_contact and not by_follow_back then
    perform private.fail('not_eligible');
  end if;

  insert into public.follow_requests (requester_id, target_id, source)
  values (uid, p_target_id, case when by_contact then 'contact'::public.request_source else 'follow_back'::public.request_source end)
  returning id into new_id;

  insert into public.activity (recipient_id, actor_id, type, request_id)
  values (p_target_id, uid, 'follow_request', new_id);

  perform private.enqueue_push(p_target_id, 'follow_request', uid,
    jsonb_build_object('request_id', new_id, 'source', case when by_contact then 'contact' else 'follow_back' end));

  return new_id;
end;
$$;

create function public.cancel_follow_request(p_request_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  update public.follow_requests
     set status = 'cancelled', resolved_at = now()
   where id = p_request_id and requester_id = uid and status in ('pending', 'declined');
  if not found then
    perform private.fail('request_not_found');
  end if;
  delete from public.activity where request_id = p_request_id and type = 'follow_request';
end;
$$;

create function public.approve_follow_request(p_request_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  req public.follow_requests%rowtype;
  follow_back_available boolean;
begin
  select * into req from public.follow_requests
   where id = p_request_id and target_id = uid and status = 'pending'
   for update;
  if not found then
    perform private.fail('request_not_found');
  end if;

  update public.follow_requests set status = 'approved', resolved_at = now() where id = req.id;

  insert into public.follows (follower_id, followee_id)
  values (req.requester_id, uid)
  on conflict do nothing;

  -- The request item in the approver's activity is resolved; the requester
  -- gets an approval item.
  delete from public.activity where request_id = req.id and type = 'follow_request';
  insert into public.activity (recipient_id, actor_id, type, request_id)
  values (req.requester_id, uid, 'request_approved', req.id);

  perform private.enqueue_push(req.requester_id, 'request_approved', uid,
    jsonb_build_object('request_id', req.id));

  follow_back_available :=
    not exists (select 1 from public.follows f where f.follower_id = uid and f.followee_id = req.requester_id)
    and not exists (select 1 from public.follow_requests r
                     where r.requester_id = uid and r.target_id = req.requester_id
                       and r.status in ('pending', 'declined'));

  return jsonb_build_object(
    'requester_id', req.requester_id,
    'follow_back_available', follow_back_available
  );
end;
$$;

create function public.decline_follow_request(p_request_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  update public.follow_requests
     set status = 'declined', resolved_at = now()
   where id = p_request_id and target_id = uid and status = 'pending';
  if not found then
    perform private.fail('request_not_found');
  end if;
  -- Nothing is written for the requester (A1).
  delete from public.activity where request_id = p_request_id and type = 'follow_request';
end;
$$;

create function public.unfollow(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  delete from public.follows where follower_id = uid and followee_id = p_user_id;
  delete from public.bells where user_id = uid and target_id = p_user_id;
end;
$$;

create function public.remove_follower(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  -- No activity, no push (spec 3.5).
  delete from public.follows where follower_id = p_user_id and followee_id = uid;
  delete from public.bells where user_id = p_user_id and target_id = uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Media and posts
-- ---------------------------------------------------------------------------
create function private.new_object_key(p_owner uuid, p_kind public.media_kind)
returns text
language sql volatile
set search_path = ''
as $$
  select 'media/' || p_owner || '/' || gen_random_uuid() || case when p_kind = 'video' then '.mp4' else '.jpg' end;
$$;
revoke execute on function private.new_object_key(uuid, public.media_kind) from public, anon, authenticated;

-- Creates a post with its media rows in pending state. p_media is a JSON array
-- of {"kind": "photo"|"video", "duration_s": number|null} in display order.
create function public.create_post(
  p_caption text,
  p_location_name text,
  p_location_lat double precision,
  p_location_lng double precision,
  p_responses_enabled boolean,
  p_media jsonb
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  n integer := coalesce(jsonb_array_length(p_media), 0);
  item jsonb;
  idx integer := 0;
  post_id uuid;
  kind public.media_kind;
  duration numeric;
  key text;
  result jsonb := '[]'::jsonb;
  media_id uuid;
  thumb text;
begin
  if jsonb_typeof(p_media) is distinct from 'array' or n < 1 or n > 10 then
    perform private.fail('media_count_invalid');
  end if;
  if char_length(coalesce(p_caption, '')) > 1000 then
    perform private.fail('caption_too_long');
  end if;

  insert into public.posts (author_id, caption, location_name, location_lat, location_lng, responses_enabled)
  values (uid, coalesce(p_caption, ''), nullif(trim(p_location_name), ''), p_location_lat, p_location_lng,
          coalesce(p_responses_enabled, true))
  returning id into post_id;

  for item in select * from jsonb_array_elements(p_media) loop
    kind := (item ->> 'kind')::public.media_kind;
    duration := (item ->> 'duration_s')::numeric;
    if kind = 'video' and (duration is null or duration > 60) then
      perform private.fail('video_too_long');
    end if;
    key := private.new_object_key(uid, kind);
    thumb := regexp_replace(key, '\.(jpg|mp4)$', '_thumb.jpg');
    insert into public.media (owner_id, post_id, usage, kind, object_key, thumb_key, duration_s, position)
    values (uid, post_id, 'post', kind, key, thumb, case when kind = 'video' then duration end, idx)
    returning id into media_id;
    result := result || jsonb_build_object('id', media_id, 'object_key', key, 'thumb_key', thumb, 'position', idx, 'kind', kind);
    idx := idx + 1;
  end loop;

  return jsonb_build_object('post_id', post_id, 'media', result);
end;
$$;

-- A single media row for an avatar or a story.
create function public.create_media(p_usage public.media_usage, p_kind public.media_kind, p_duration_s numeric default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  key text;
  thumb text;
  media_id uuid;
begin
  if p_usage = 'post' then
    perform private.fail('use_create_post');
  end if;
  if p_usage = 'avatar' and p_kind <> 'photo' then
    perform private.fail('avatar_must_be_photo');
  end if;
  if p_kind = 'video' and (p_duration_s is null or p_duration_s > 60) then
    perform private.fail('video_too_long');
  end if;
  key := private.new_object_key(uid, p_kind);
  thumb := regexp_replace(key, '\.(jpg|mp4)$', '_thumb.jpg');
  insert into public.media (owner_id, usage, kind, object_key, thumb_key, duration_s)
  values (uid, p_usage, p_kind, key, thumb, case when p_kind = 'video' then p_duration_s end)
  returning id into media_id;
  return jsonb_build_object('id', media_id, 'object_key', key, 'thumb_key', thumb, 'kind', p_kind);
end;
$$;

create function public.mark_media_ready(
  p_media_id uuid,
  p_width integer,
  p_height integer,
  p_duration_s numeric default null,
  p_bytes bigint default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if p_duration_s is not null and p_duration_s > 60 then
    perform private.fail('video_too_long');
  end if;
  update public.media
     set status = 'ready',
         width = p_width,
         height = p_height,
         duration_s = coalesce(p_duration_s, duration_s),
         bytes = p_bytes
   where id = p_media_id and owner_id = uid;
  if not found then
    perform private.fail('media_not_found');
  end if;
end;
$$;

create function public.publish_post(p_post_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  pending_count integer;
  media_count integer;
  r record;
begin
  if not exists (select 1 from public.posts p where p.id = p_post_id and p.author_id = uid) then
    perform private.fail('post_not_found');
  end if;
  select count(*), count(*) filter (where status <> 'ready')
    into media_count, pending_count
    from public.media where post_id = p_post_id;
  if media_count < 1 then
    perform private.fail('media_count_invalid');
  end if;
  if pending_count > 0 then
    perform private.fail('media_not_ready');
  end if;

  update public.posts set published_at = coalesce(published_at, now()) where id = p_post_id;

  -- "Notify me" bells (spec 10): followers who turned on the bell for this author.
  for r in
    select b.user_id from public.bells b
    join public.follows f on f.follower_id = b.user_id and f.followee_id = uid
    where b.target_id = uid
  loop
    perform private.enqueue_push(r.user_id, 'bell_post', uid, jsonb_build_object('post_id', p_post_id));
  end loop;
end;
$$;

create function public.update_post(
  p_post_id uuid,
  p_caption text,
  p_location_name text,
  p_location_lat double precision,
  p_location_lng double precision,
  p_responses_enabled boolean
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if char_length(coalesce(p_caption, '')) > 1000 then
    perform private.fail('caption_too_long');
  end if;
  update public.posts
     set caption = coalesce(p_caption, ''),
         location_name = nullif(trim(p_location_name), ''),
         location_lat = p_location_lat,
         location_lng = p_location_lng,
         responses_enabled = coalesce(p_responses_enabled, responses_enabled)
   where id = p_post_id and author_id = uid;
  if not found then
    perform private.fail('post_not_found');
  end if;
end;
$$;

create function public.delete_post(p_post_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  -- Media rows cascade; messages keep kind = post_response with post_id null
  -- ("Post no longer available"). Objects are removed by cleanup-orphans.
  delete from public.posts where id = p_post_id and author_id = uid;
  if not found then
    perform private.fail('post_not_found');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Likes
-- ---------------------------------------------------------------------------
create function public.like_post(p_post_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  author uuid;
begin
  select p.author_id into author from public.posts p
   where p.id = p_post_id and p.published_at is not null
     and private.can_view_content(uid, p.author_id);
  if author is null then
    perform private.fail('post_not_found');
  end if;
  insert into public.likes (post_id, user_id) values (p_post_id, uid)
  on conflict do nothing;
  if found and author <> uid then
    insert into public.activity (recipient_id, actor_id, type, post_id)
    values (author, uid, 'like', p_post_id);
    -- No push for likes (spec 10).
  end if;
end;
$$;

create function public.unlike_post(p_post_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  delete from public.likes where post_id = p_post_id and user_id = uid;
  delete from public.activity where post_id = p_post_id and actor_id = uid and type = 'like';
end;
$$;

-- ---------------------------------------------------------------------------
-- Stories
-- ---------------------------------------------------------------------------
create function public.create_story(p_media_id uuid, p_location_name text default null, p_replies_enabled boolean default true)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  story_id uuid;
  r record;
begin
  if not exists (
    select 1 from public.media m
    where m.id = p_media_id and m.owner_id = uid and m.usage = 'story' and m.status = 'ready'
  ) then
    perform private.fail('media_not_ready');
  end if;
  insert into public.stories (author_id, media_id, location_name, replies_enabled)
  values (uid, p_media_id, nullif(trim(p_location_name), ''), coalesce(p_replies_enabled, true))
  returning id into story_id;

  for r in
    select b.user_id from public.bells b
    join public.follows f on f.follower_id = b.user_id and f.followee_id = uid
    where b.target_id = uid
  loop
    perform private.enqueue_push(r.user_id, 'bell_story', uid, jsonb_build_object('story_id', story_id));
  end loop;
  return story_id;
end;
$$;

create function public.delete_story(p_story_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  delete from public.stories where id = p_story_id and author_id = uid;
  if not found then
    perform private.fail('story_not_found');
  end if;
end;
$$;

create function public.mark_story_viewed(p_story_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if not exists (
    select 1 from public.stories s
    where s.id = p_story_id and s.author_id <> uid
      and s.expires_at > now() and private.can_view_content(uid, s.author_id)
  ) then
    perform private.fail('story_not_found');
  end if;
  insert into public.story_views (story_id, viewer_id) values (p_story_id, uid)
  on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Messaging (spec 7). A conversation is only ever created by a response.
-- ---------------------------------------------------------------------------
create function private.find_or_create_conversation(p_a uuid, p_b uuid)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  lo uuid := least(p_a, p_b);
  hi uuid := greatest(p_a, p_b);
  cid uuid;
begin
  insert into public.conversations (user_a, user_b) values (lo, hi)
  on conflict (user_a, user_b) do update set user_a = excluded.user_a
  returning id into cid;
  return cid;
end;
$$;
revoke execute on function private.find_or_create_conversation(uuid, uuid) from public, anon, authenticated;

create function private.insert_message(
  p_conversation uuid, p_sender uuid, p_recipient uuid, p_kind public.message_kind,
  p_body text, p_post uuid, p_story uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  mid uuid;
  created timestamptz;
begin
  if p_body is null or trim(p_body) = '' then
    perform private.fail('message_empty');
  end if;
  if char_length(p_body) > 2000 then
    perform private.fail('message_too_long');
  end if;
  insert into public.messages (conversation_id, sender_id, kind, body, post_id, story_id)
  values (p_conversation, p_sender, p_kind, p_body, p_post, p_story)
  returning id, created_at into mid, created;
  update public.conversations set last_message_at = created where id = p_conversation;
  insert into public.conversation_reads (conversation_id, user_id, last_read_at)
  values (p_conversation, p_sender, created)
  on conflict (conversation_id, user_id) do update set last_read_at = excluded.last_read_at;
  -- The push carries no body (spec 11: logs must not contain messages).
  perform private.enqueue_push(p_recipient, 'message', p_sender,
    jsonb_build_object('conversation_id', p_conversation, 'message_id', mid, 'kind', p_kind));
  return jsonb_build_object('id', mid, 'conversation_id', p_conversation, 'created_at', created);
end;
$$;
revoke execute on function private.insert_message(uuid, uuid, uuid, public.message_kind, text, uuid, uuid) from public, anon, authenticated;

create function public.respond_to_post(p_post_id uuid, p_body text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  post public.posts%rowtype;
  cid uuid;
begin
  select * into post from public.posts p
   where p.id = p_post_id and p.published_at is not null
     and private.can_view_content(uid, p.author_id);
  if not found then
    perform private.fail('post_not_found');
  end if;
  if post.author_id = uid then
    perform private.fail('own_post');
  end if;
  if not post.responses_enabled then
    perform private.fail('responses_off');
  end if;
  cid := private.find_or_create_conversation(uid, post.author_id);
  return private.insert_message(cid, uid, post.author_id, 'post_response', p_body, p_post_id, null);
end;
$$;

create function public.respond_to_story(p_story_id uuid, p_body text, p_is_reaction boolean default false)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  story public.stories%rowtype;
  cid uuid;
begin
  select * into story from public.stories s
   where s.id = p_story_id and s.expires_at > now()
     and private.can_view_content(uid, s.author_id);
  if not found then
    perform private.fail('story_not_found');
  end if;
  if story.author_id = uid then
    perform private.fail('own_story');
  end if;
  if not story.replies_enabled then
    perform private.fail('replies_off');
  end if;
  cid := private.find_or_create_conversation(uid, story.author_id);
  return private.insert_message(cid, uid, story.author_id,
    case when p_is_reaction then 'story_reaction'::public.message_kind else 'story_response'::public.message_kind end,
    p_body, null, p_story_id);
end;
$$;

-- Whether two people may still message each other: at least one follows the other.
create function private.can_message(p_a uuid, p_b uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (
    select 1 from public.follows f
    where (f.follower_id = p_a and f.followee_id = p_b)
       or (f.follower_id = p_b and f.followee_id = p_a)
  );
$$;
revoke execute on function private.can_message(uuid, uuid) from public, anon, authenticated;

create function public.send_message(p_conversation_id uuid, p_body text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  conv public.conversations%rowtype;
  other uuid;
begin
  select * into conv from public.conversations c
   where c.id = p_conversation_id and (c.user_a = uid or c.user_b = uid);
  if not found then
    perform private.fail('conversation_not_found');
  end if;
  other := case when conv.user_a = uid then conv.user_b else conv.user_a end;
  if not private.can_message(uid, other) then
    perform private.fail('conversation_read_only');
  end if;
  return private.insert_message(conv.id, uid, other, 'text', p_body, null, null);
end;
$$;

create function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if not exists (select 1 from public.conversations c
                  where c.id = p_conversation_id and (c.user_a = uid or c.user_b = uid)) then
    perform private.fail('conversation_not_found');
  end if;
  insert into public.conversation_reads (conversation_id, user_id, last_read_at)
  values (p_conversation_id, uid, now())
  on conflict (conversation_id, user_id) do update set last_read_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Own-data settings
-- ---------------------------------------------------------------------------
create function public.mark_feed_seen(p_through timestamptz)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  insert into public.feed_seen (user_id, seen_through) values (uid, p_through)
  on conflict (user_id) do update
    set seen_through = greatest(public.feed_seen.seen_through, excluded.seen_through), updated_at = now();
end;
$$;

create function public.set_bell(p_target_id uuid, p_enabled boolean)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if p_enabled then
    if not exists (select 1 from public.follows f where f.follower_id = uid and f.followee_id = p_target_id) then
      perform private.fail('not_following');
    end if;
    insert into public.bells (user_id, target_id) values (uid, p_target_id) on conflict do nothing;
  else
    delete from public.bells where user_id = uid and target_id = p_target_id;
  end if;
end;
$$;

create function public.update_notification_settings(p_requests boolean, p_messages boolean, p_likes boolean, p_bells boolean)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  insert into public.notification_settings (user_id, requests, messages, likes, bells)
  values (uid, coalesce(p_requests, true), coalesce(p_messages, true), coalesce(p_likes, true), coalesce(p_bells, true))
  on conflict (user_id) do update
    set requests = excluded.requests, messages = excluded.messages,
        likes = excluded.likes, bells = excluded.bells, updated_at = now();
end;
$$;

create function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if p_token is null or length(p_token) < 8 or length(p_token) > 512 then
    perform private.fail('invalid_token');
  end if;
  insert into public.device_tokens (token, user_id, platform) values (p_token, uid, p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;

create function public.unregister_device_token(p_token text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  delete from public.device_tokens where token = p_token and user_id = uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants: the write API available to signed-in clients.
-- ---------------------------------------------------------------------------
grant execute on function
  public.update_profile(text, text, text, uuid, boolean),
  public.get_me(),
  public.match_contacts(text[]),
  public.send_follow_request(uuid, text),
  public.cancel_follow_request(uuid),
  public.approve_follow_request(uuid),
  public.decline_follow_request(uuid),
  public.unfollow(uuid),
  public.remove_follower(uuid),
  public.create_post(text, text, double precision, double precision, boolean, jsonb),
  public.create_media(public.media_usage, public.media_kind, numeric),
  public.mark_media_ready(uuid, integer, integer, numeric, bigint),
  public.publish_post(uuid),
  public.update_post(uuid, text, text, double precision, double precision, boolean),
  public.delete_post(uuid),
  public.like_post(uuid),
  public.unlike_post(uuid),
  public.create_story(uuid, text, boolean),
  public.delete_story(uuid),
  public.mark_story_viewed(uuid),
  public.respond_to_post(uuid, text),
  public.respond_to_story(uuid, text, boolean),
  public.send_message(uuid, text),
  public.mark_conversation_read(uuid),
  public.mark_feed_seen(timestamptz),
  public.set_bell(uuid, boolean),
  public.update_notification_settings(boolean, boolean, boolean, boolean),
  public.register_device_token(text, text),
  public.unregister_device_token(text)
to authenticated;

-- Postgres grants EXECUTE to PUBLIC on new functions regardless of default
-- privileges, so strip it explicitly. Signed-in clients keep the grants above.
revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema private from public, anon, authenticated;
