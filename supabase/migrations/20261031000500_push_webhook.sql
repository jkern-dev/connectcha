-- Push delivery plumbing (plan 3.5 send-push, M8).
--
-- Every insert into push_outbox fires an HTTP call to the send-push Edge
-- Function (a "database webhook" built on pg_net). The function loads the
-- recipient's settings and device tokens and talks to APNs. Locally APNs is
-- stubbed: deliveries are recorded in push_deliveries and a bridge script
-- hands them to the simulators with `xcrun simctl push`.

create extension if not exists pg_net with schema extensions;

-- Simulator / stub deliveries written by send-push when APNS_MODE=stub.
create table public.push_deliveries (
  id bigint generated always as identity primary key,
  outbox_id bigint references public.push_outbox (id) on delete cascade,
  token text not null,
  platform text not null,
  -- The exact APNs payload (aps + custom keys). Contains ids, a type and the
  -- actor's profile name; never message bodies, numbers or hashes.
  payload jsonb not null,
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);
alter table public.push_deliveries enable row level security;
revoke all on public.push_deliveries from anon, authenticated;

-- Where the webhook should call. Stored in a tiny settings table so the
-- trigger has no hard-coded URL; the local seed and the hosted project set it.
create table private.settings (
  key text primary key,
  value text not null
);

create function private.setting(p_key text)
returns text
language sql stable
set search_path = ''
as $$
  select value from private.settings where key = p_key;
$$;
revoke execute on function private.setting(text) from public, anon, authenticated;

-- Trigger: POST the new outbox row to send-push.
create function private.notify_send_push()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  url text := private.setting('push_webhook_url');
  secret text := coalesce(private.setting('push_webhook_secret'), '');
begin
  if url is null then
    return new;   -- push not configured in this environment
  end if;
  perform net.http_post(
    url := url,
    body := jsonb_build_object('outbox_id', new.id),
    headers := jsonb_build_object('content-type', 'application/json', 'x-webhook-secret', secret),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;
revoke execute on function private.notify_send_push() from public, anon, authenticated;

create trigger push_outbox_notify
  after insert on public.push_outbox
  for each row execute function private.notify_send_push();

-- Service-side helpers used by send-push (service role only).
create function public.push_job(p_outbox_id bigint)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'outbox', to_jsonb(o),
    'settings', (select to_jsonb(n) from public.notification_settings n where n.user_id = o.recipient_id),
    'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', d.token, 'platform', d.platform))
                          from public.device_tokens d where d.user_id = o.recipient_id), '[]'::jsonb)
  )
  from public.push_outbox o where o.id = p_outbox_id;
$$;
revoke execute on function public.push_job(bigint) from public, anon, authenticated;
grant execute on function public.push_job(bigint) to service_role;

create function public.push_mark_sent(p_outbox_id bigint, p_deliveries jsonb default '[]'::jsonb, p_dead_tokens text[] default '{}')
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  update public.push_outbox set sent_at = now(), attempts = attempts + 1 where id = p_outbox_id;
  insert into public.push_deliveries (outbox_id, token, platform, payload)
  select p_outbox_id, d ->> 'token', d ->> 'platform', d -> 'payload'
  from jsonb_array_elements(coalesce(p_deliveries, '[]'::jsonb)) d;
  delete from public.device_tokens where token = any (p_dead_tokens);
end;
$$;
revoke execute on function public.push_mark_sent(bigint, jsonb, text[]) from public, anon, authenticated;
grant execute on function public.push_mark_sent(bigint, jsonb, text[]) to service_role;

-- Pending simulator deliveries for the bridge script (service role only).
create function public.push_pending_deliveries()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'token', d.token, 'payload', d.payload) order by d.id), '[]'::jsonb)
  from public.push_deliveries d where d.delivered_at is null and d.platform = 'ios_simulator';
$$;
create function public.push_mark_delivered(p_ids bigint[])
returns void
language sql security definer
set search_path = ''
as $$
  update public.push_deliveries set delivered_at = now() where id = any (p_ids);
$$;
revoke execute on function public.push_pending_deliveries() from public, anon, authenticated;
revoke execute on function public.push_mark_delivered(bigint[]) from public, anon, authenticated;
grant execute on function public.push_pending_deliveries() to service_role;
grant execute on function public.push_mark_delivered(bigint[]) to service_role;

-- Debug builds on a simulator may poll their own stubbed deliveries and show
-- them as local notifications (used by the UI tests). Callers only ever see
-- deliveries addressed to tokens they registered themselves.
create function public.my_pending_pushes()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'payload', d.payload) order by d.id), '[]'::jsonb)
  from public.push_deliveries d
  join public.device_tokens t on t.token = d.token
  where t.user_id = auth.uid() and d.delivered_at is null and d.platform = 'ios_simulator';
$$;

create function public.ack_pushes(p_ids bigint[])
returns void
language sql security definer
set search_path = ''
as $$
  update public.push_deliveries d set delivered_at = now()
  from public.device_tokens t
  where d.id = any (p_ids) and t.token = d.token and t.user_id = auth.uid();
$$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.my_pending_pushes() to authenticated;
grant execute on function public.ack_pushes(bigint[]) to authenticated;
