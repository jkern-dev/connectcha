-- Server-side enforcement of "US (+1) numbers only" (spec 2, scenario 10).
--
-- Production also blocks non-US numbers at Twilio through Verify Geo
-- Permissions, but this hook makes the rule hold regardless of provider and
-- stops GoTrue from creating a user row before the text is even attempted.
-- Registered in config.toml under [auth.hook.before_user_created].

create or replace function public.before_user_created_hook(event jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  phone text := event -> 'user' ->> 'phone';
begin
  -- Phone sign-ups must be a US number: country code 1 followed by ten digits.
  -- (Email sign-ups are disabled in config and never reach here in the app.)
  if phone is null or phone = '' then
    return '{}'::jsonb;
  end if;

  if phone !~ '^1[2-9][0-9]{9}$' then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message', 'Only US phone numbers can sign up right now.'
      )
    );
  end if;

  return '{}'::jsonb;
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.before_user_created_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.before_user_created_hook(jsonb) from public, anon, authenticated;
revoke execute on all functions in schema public from public, anon;
