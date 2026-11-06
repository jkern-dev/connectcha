-- In-app account deletion (D-34; Apple guideline 5.1.1(v)).
--
-- Deleting the auth.users row cascades through profiles and every table that
-- references it: posts, media rows, stories, follows, requests, likes, bells,
-- activity, device tokens, notification settings, and conversations the person
-- was part of (with every message in them, theirs and the other person's).
-- Bucket objects for the deleted media rows become orphans and the daily
-- cleanup-orphans run removes them.

create function public.delete_my_account()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  delete from auth.users where id = uid;
end;
$$;

grant execute on function public.delete_my_account() to authenticated;
revoke execute on function public.delete_my_account() from public, anon;
