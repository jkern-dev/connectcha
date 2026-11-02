-- Read models: one function per screen, returning JSON the app renders
-- directly. All run as SECURITY DEFINER with the viewer fixed to auth.uid(),
-- and every row they return passes the same helpers the row-level policies
-- use (private.can_view_content, private.can_see_profile). Names are always
-- profile names; the phone substitutes saved contact names on the device.

-- ---------------------------------------------------------------------------
-- JSON building blocks
-- ---------------------------------------------------------------------------
create function private.profile_json(p_user uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'first_name', p.first_name,
    'last_name', p.last_name,
    'avatar_media_id', p.avatar_media_id
  )
  from public.profiles p where p.id = p_user;
$$;
revoke execute on function private.profile_json(uuid) from public, anon, authenticated;

create function private.media_json(p_media_id uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', m.id,
    'kind', m.kind,
    'width', m.width,
    'height', m.height,
    'duration_s', m.duration_s,
    'position', m.position,
    'status', m.status
  )
  from public.media m where m.id = p_media_id;
$$;
revoke execute on function private.media_json(uuid) from public, anon, authenticated;

create function private.post_json(p_post_id uuid, p_viewer uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'author', private.profile_json(p.author_id),
    'is_mine', p.author_id = p_viewer,
    'caption', p.caption,
    'location_name', p.location_name,
    'location_lat', p.location_lat,
    'location_lng', p.location_lng,
    'responses_enabled', p.responses_enabled,
    'published_at', p.published_at,
    'media', coalesce((
      select jsonb_agg(private.media_json(m.id) order by m.position)
      from public.media m where m.post_id = p.id), '[]'::jsonb),
    'like_count', (select count(*) from public.likes l where l.post_id = p.id),
    'liked_by_me', exists (select 1 from public.likes l where l.post_id = p.id and l.user_id = p_viewer)
  )
  from public.posts p where p.id = p_post_id;
$$;
revoke execute on function private.post_json(uuid, uuid) from public, anon, authenticated;

create function private.story_json(p_story_id uuid, p_viewer uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', s.id,
    'author', private.profile_json(s.author_id),
    'is_mine', s.author_id = p_viewer,
    'media', private.media_json(s.media_id),
    'location_name', s.location_name,
    'replies_enabled', s.replies_enabled,
    'created_at', s.created_at,
    'expires_at', s.expires_at,
    'seen', s.author_id = p_viewer
            or exists (select 1 from public.story_views v where v.story_id = s.id and v.viewer_id = p_viewer),
    'view_count', case when s.author_id = p_viewer
                       then (select count(*) from public.story_views v where v.story_id = s.id) end
  )
  from public.stories s where s.id = p_story_id;
$$;
revoke execute on function private.story_json(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Feed (spec 5.1): newest first, only people you follow plus yourself, with
-- the "You're all caught up" marker (G7).
-- ---------------------------------------------------------------------------
create function public.get_feed(p_before timestamptz default null, p_limit integer default 20)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  lim integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  return jsonb_build_object(
    'posts', coalesce((
      select jsonb_agg(private.post_json(x.id, uid) order by x.published_at desc, x.id desc)
      from (
        select p.id, p.published_at
        from public.posts p
        where p.published_at is not null
          and (p_before is null or p.published_at < p_before)
          and private.can_view_content(uid, p.author_id)
        order by p.published_at desc, p.id desc
        limit lim
      ) x), '[]'::jsonb),
    'seen_through', (select f.seen_through from public.feed_seen f where f.user_id = uid)
  );
end;
$$;

create function public.get_post(p_post_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if not exists (
    select 1 from public.posts p where p.id = p_post_id
      and (p.author_id = uid or (p.published_at is not null and private.can_view_content(uid, p.author_id)))
  ) then
    perform private.fail('post_not_found');
  end if;
  return private.post_json(p_post_id, uid);
end;
$$;

-- Only the poster can see who liked (spec 5.3).
create function public.get_post_likers(p_post_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if not exists (select 1 from public.posts p where p.id = p_post_id and p.author_id = uid) then
    perform private.fail('post_not_found');
  end if;
  return coalesce((
    select jsonb_agg(private.profile_json(l.user_id) order by l.created_at desc)
    from public.likes l where l.post_id = p_post_id), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Profiles (spec 8.1 to 8.4). p_phone_hash lets the caller open a matched
-- contact's minimal profile before any relationship exists.
-- ---------------------------------------------------------------------------
create function public.get_profile(p_user_id uuid, p_phone_hash text default null)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  prof public.profiles%rowtype;
  can_see boolean;
  can_view boolean;
  i_follow boolean;
  follows_me boolean;
begin
  select * into prof from public.profiles p where p.id = p_user_id and p.onboarded_at is not null;
  if not found then
    perform private.fail('profile_not_found');
  end if;

  can_see := private.can_see_profile(uid, p_user_id)
             or (p_phone_hash is not null and prof.phone_hash = p_phone_hash);
  if not can_see then
    perform private.fail('profile_not_found');
  end if;

  can_view := private.can_view_content(uid, p_user_id);
  i_follow := exists (select 1 from public.follows f where f.follower_id = uid and f.followee_id = p_user_id);
  follows_me := exists (select 1 from public.follows f where f.follower_id = p_user_id and f.followee_id = uid);

  return jsonb_build_object(
    'profile', private.profile_json(p_user_id),
    'is_me', p_user_id = uid,
    'can_view', can_view,
    'bio', case when can_view then prof.bio end,
    'relationship', jsonb_build_object(
      'i_follow', i_follow,
      'follows_me', follows_me,
      'outgoing_request_id', (select r.id from public.follow_requests r
                               where r.requester_id = uid and r.target_id = p_user_id
                                 and r.status in ('pending', 'declined') limit 1),
      'incoming_request_id', (select r.id from public.follow_requests r
                               where r.requester_id = p_user_id and r.target_id = uid
                                 and r.status = 'pending' limit 1),
      -- Follow-back eligibility is server-known; contact eligibility is the phone's knowledge.
      'follow_back_eligible', follows_me and not i_follow,
      'bell_on', exists (select 1 from public.bells b where b.user_id = uid and b.target_id = p_user_id),
      'has_conversation', exists (select 1 from public.conversations c
                                   where c.user_a = least(uid, p_user_id) and c.user_b = greatest(uid, p_user_id))
    ),
    'has_active_story', can_view and exists (
      select 1 from public.stories s where s.author_id = p_user_id and s.expires_at > now()),
    'posts', case when can_view then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'published_at', p.published_at,
        'media_count', (select count(*) from public.media m where m.post_id = p.id),
        'cover', (select private.media_json(m.id) from public.media m
                   where m.post_id = p.id order by m.position limit 1)
      ) order by p.published_at desc)
      from public.posts p where p.author_id = p_user_id and p.published_at is not null), '[]'::jsonb)
    else '[]'::jsonb end
  );
end;
$$;

-- Own follower and following lists (spec 8.2). Nobody else has an equivalent.
create function public.get_my_connections()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'followers', coalesce((
      select jsonb_agg(private.profile_json(f.follower_id) order by f.created_at desc)
      from public.follows f where f.followee_id = uid), '[]'::jsonb),
    'following', coalesce((
      select jsonb_agg(private.profile_json(f.followee_id) || jsonb_build_object(
        'bell_on', exists (select 1 from public.bells b where b.user_id = uid and b.target_id = f.followee_id))
        order by f.created_at desc)
      from public.follows f where f.follower_id = uid), '[]'::jsonb)
  );
end;
$$;

-- People tab data (spec 3.4, 8.5): incoming requests and the ids you have
-- outstanding requests to (so matched contacts show "Requested").
create function public.get_people()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'incoming', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'requester', private.profile_json(r.requester_id),
        'source', r.source,
        'created_at', r.created_at
      ) order by r.created_at desc)
      from public.follow_requests r where r.target_id = uid and r.status = 'pending'), '[]'::jsonb),
    'outgoing', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'target_id', r.target_id, 'source', r.source, 'created_at', r.created_at)
        order by r.created_at desc)
      from public.follow_requests r where r.requester_id = uid and r.status in ('pending', 'declined')), '[]'::jsonb),
    'following_ids', coalesce((
      select jsonb_agg(f.followee_id) from public.follows f where f.follower_id = uid), '[]'::jsonb),
    'follower_ids', coalesce((
      select jsonb_agg(f.follower_id) from public.follows f where f.followee_id = uid), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Stories (spec 6)
-- ---------------------------------------------------------------------------
create function public.get_story_tray()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'author', private.profile_json(g.author_id),
      'is_mine', g.author_id = uid,
      'latest_at', g.latest_at,
      'all_seen', g.all_seen,
      'stories', g.stories
    ) order by (g.author_id = uid) desc, g.all_seen asc, g.latest_at desc)
    from (
      select s.author_id,
             max(s.created_at) as latest_at,
             bool_and(s.author_id = uid or exists (
               select 1 from public.story_views v where v.story_id = s.id and v.viewer_id = uid)) as all_seen,
             jsonb_agg(private.story_json(s.id, uid) order by s.created_at asc) as stories
      from public.stories s
      where s.expires_at > now()
        and private.can_view_content(uid, s.author_id)
      group by s.author_id
    ) g), '[]'::jsonb);
end;
$$;

create function public.get_story_viewers(p_story_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if not exists (select 1 from public.stories s where s.id = p_story_id and s.author_id = uid) then
    perform private.fail('story_not_found');
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('viewer', private.profile_json(v.viewer_id), 'viewed_at', v.viewed_at)
      order by v.viewed_at desc)
    from public.story_views v where v.story_id = p_story_id), '[]'::jsonb);
end;
$$;

-- Every story of your own, active or expired (the private archive).
create function public.get_my_story_archive()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return coalesce((
    select jsonb_agg(private.story_json(s.id, uid) order by s.created_at desc)
    from public.stories s where s.author_id = uid), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Messaging (spec 7)
-- ---------------------------------------------------------------------------
create function private.message_json(p_message_id uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', m.id,
    'conversation_id', m.conversation_id,
    'sender_id', m.sender_id,
    'kind', m.kind,
    'body', m.body,
    'created_at', m.created_at,
    -- Previews: null means "no longer available" (deleted post, or expired story, A2).
    'post', (select jsonb_build_object(
               'id', p.id,
               'author', private.profile_json(p.author_id),
               'cover', (select private.media_json(md.id) from public.media md
                          where md.post_id = p.id order by md.position limit 1))
             from public.posts p where p.id = m.post_id),
    'story', (select jsonb_build_object(
                'id', s.id,
                'author', private.profile_json(s.author_id),
                'media', private.media_json(s.media_id))
              from public.stories s where s.id = m.story_id and s.expires_at > now())
  )
  from public.messages m where m.id = p_message_id;
$$;
revoke execute on function private.message_json(uuid) from public, anon, authenticated;

create function public.get_inbox()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'conversation_id', c.id,
      'other', private.profile_json(case when c.user_a = uid then c.user_b else c.user_a end),
      'last_message_at', c.last_message_at,
      'last_message', (select private.message_json(m.id) from public.messages m
                        where m.conversation_id = c.id order by m.created_at desc limit 1),
      'unread', exists (
        select 1 from public.messages m
        where m.conversation_id = c.id and m.sender_id <> uid
          and m.created_at > coalesce((select r.last_read_at from public.conversation_reads r
                                        where r.conversation_id = c.id and r.user_id = uid), '-infinity'::timestamptz)),
      'can_send', private.can_message(c.user_a, c.user_b)
    ) order by c.last_message_at desc)
    from public.conversations c
    where c.user_a = uid or c.user_b = uid), '[]'::jsonb);
end;
$$;

create function public.get_conversation(p_conversation_id uuid, p_before timestamptz default null, p_limit integer default 50)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  conv public.conversations%rowtype;
  other uuid;
  lim integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  select * into conv from public.conversations c
   where c.id = p_conversation_id and (c.user_a = uid or c.user_b = uid);
  if not found then
    perform private.fail('conversation_not_found');
  end if;
  other := case when conv.user_a = uid then conv.user_b else conv.user_a end;
  return jsonb_build_object(
    'conversation_id', conv.id,
    'other', private.profile_json(other),
    'can_send', private.can_message(uid, other),
    'messages', coalesce((
      select jsonb_agg(private.message_json(x.id) order by x.created_at asc)
      from (
        select m.id, m.created_at from public.messages m
        where m.conversation_id = conv.id
          and (p_before is null or m.created_at < p_before)
        order by m.created_at desc
        limit lim
      ) x), '[]'::jsonb)
  );
end;
$$;

create function public.get_message(p_message_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if not exists (
    select 1 from public.messages m join public.conversations c on c.id = m.conversation_id
    where m.id = p_message_id and (c.user_a = uid or c.user_b = uid)
  ) then
    perform private.fail('message_not_found');
  end if;
  return private.message_json(p_message_id);
end;
$$;

create function public.get_unread_counts()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'unread_conversations', (
      select count(*) from public.conversations c
      where (c.user_a = uid or c.user_b = uid)
        and exists (
          select 1 from public.messages m
          where m.conversation_id = c.id and m.sender_id <> uid
            and m.created_at > coalesce((select r.last_read_at from public.conversation_reads r
                                          where r.conversation_id = c.id and r.user_id = uid), '-infinity'::timestamptz))),
    'pending_requests', (select count(*) from public.follow_requests r where r.target_id = uid and r.status = 'pending')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Activity (spec 10 in-app column). Likes are grouped by the client.
-- ---------------------------------------------------------------------------
create function public.get_activity(p_limit integer default 100)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id,
      'type', a.type,
      'actor', private.profile_json(a.actor_id),
      'created_at', a.created_at,
      'request_id', a.request_id,
      'request_source', (select r.source from public.follow_requests r where r.id = a.request_id),
      'request_pending', exists (select 1 from public.follow_requests r where r.id = a.request_id and r.status = 'pending'),
      'post', (select jsonb_build_object(
                 'id', p.id,
                 'cover', (select private.media_json(md.id) from public.media md
                            where md.post_id = p.id order by md.position limit 1))
               from public.posts p where p.id = a.post_id)
    ) order by a.created_at desc)
    from (
      select * from public.activity a where a.recipient_id = uid
      order by a.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 200)
    ) a), '[]'::jsonb);
end;
$$;

grant execute on function
  public.get_feed(timestamptz, integer),
  public.get_post(uuid),
  public.get_post_likers(uuid),
  public.get_profile(uuid, text),
  public.get_my_connections(),
  public.get_people(),
  public.get_story_tray(),
  public.get_story_viewers(uuid),
  public.get_my_story_archive(),
  public.get_inbox(),
  public.get_conversation(uuid, timestamptz, integer),
  public.get_message(uuid),
  public.get_unread_counts(),
  public.get_activity(integer)
to authenticated;

-- Postgres grants EXECUTE to PUBLIC on new functions regardless of default
-- privileges, so strip it explicitly. Signed-in clients keep the grants above.
revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema private from public, anon, authenticated;
