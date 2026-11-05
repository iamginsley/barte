-- In-app account deletion (App Store Review Guideline 5.1.1(v)).
--
-- Deleting the auth user unlinks the person from every group (members.user_id is set null),
-- so friends keep the shared history with the name. Groups in which nobody else uses the app
-- are deleted first, because nobody could open them afterwards.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := public.require_user();
begin
  delete from public.groups g
  where exists (select 1 from public.members m where m.group_id = g.id and m.user_id = v_user)
    and not exists (
      select 1 from public.members m where m.group_id = g.id and m.user_id is not null and m.user_id <> v_user
    );

  delete from auth.users where id = v_user;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
