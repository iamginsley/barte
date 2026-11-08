-- Closing a group: once everyone is square, a group can be put away instead of deleted.
-- It stays readable for everyone; any new or changed expense opens it again by itself.

alter table public.groups add column closed_at timestamptz;

-- Closes (p_closed) or reopens a group for everyone in it.
create function public.set_group_closed(hasura_session json, p_group_id uuid, p_closed boolean)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
begin
  perform public.require_group_member(p_group_id, public.session_user_id(hasura_session));
  update public.groups
  set closed_at = case when p_closed then coalesce(closed_at, now()) end
  where id = p_group_id;
end;
$$;

-- An expense added, edited or deleted in a closed group (e.g. from a phone that hadn't caught up yet)
-- means the group isn't done after all.
create function public.reopen_group_on_expense()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.groups
  set closed_at = null
  where id = coalesce(new.group_id, old.group_id) and closed_at is not null;
  return null;
end;
$$;

create trigger expenses_reopen_group
after insert or update or delete on public.expenses
for each row execute function public.reopen_group_on_expense();
