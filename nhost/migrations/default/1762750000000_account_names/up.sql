-- Everyone who uses the app has one name, their account name, and it is the same in every group.
-- Names typed into a group (people without the app) stay as they are; joining as one of them
-- takes over its expenses and puts the account name on it. Nobody can rename someone who uses the
-- app, and changing the account name changes it in all groups at once.

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 40),
  updated_at timestamptz not null default now()
);

-- The account name, or null before the person ever gave one.
create function public.account_name(p_user uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select name from public.profiles where user_id = p_user;
$$;

-- Sets the account name (when given) and puts it on every member row of this person.
create function public.apply_account_name(p_user uuid, p_name text)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_name text := public.account_name(p_user);
begin
  if nullif(btrim(coalesce(p_name, '')), '') is not null then
    v_name := public.clean_name(p_name);
    insert into public.profiles (user_id, name) values (p_user, v_name)
    on conflict (user_id) do update set name = excluded.name, updated_at = now()
    where public.profiles.name is distinct from excluded.name;
  end if;
  if v_name is not null then
    update public.members set name = v_name where user_id = p_user and name is distinct from v_name;
  end if;
  return v_name;
end;
$$;

-- API -----------------------------------------------------------------------

-- Changing the name in "Über Barte": everywhere at once.
create function public.set_my_name(hasura_session json, p_name text)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
begin
  if nullif(btrim(coalesce(p_name, '')), '') is null then
    perform public.fail('empty_name');
  end if;
  return query select null::uuid, public.apply_account_name(v_user, p_name), null::jsonb;
end;
$$;

-- On every sign-in: returns the account name. Accounts from before names were stored get one from
-- the phone's name (`p_fallback`) or, without that, from their newest group.
create function public.sync_my_name(hasura_session json, p_fallback text default null)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_name text := public.account_name(v_user);
begin
  if v_name is null then
    v_name := coalesce(
      nullif(btrim(coalesce(p_fallback, '')), ''),
      (select name from public.members where user_id = v_user order by created_at desc limit 1)
    );
  end if;
  return query select null::uuid, public.apply_account_name(v_user, v_name), null::jsonb;
end;
$$;

-- Creating, joining and renaming use the account name ------------------------

create or replace function public.create_group(
  hasura_session json,
  p_name text,
  p_currency text,
  p_color smallint,
  p_my_name text,
  p_other_names text[] default '{}'
)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_group uuid;
  v_name text;
  -- The account name wins; the typed name only counts for an account without one yet.
  v_my_name text := coalesce(public.account_name(v_user), public.clean_name(p_my_name));
begin
  insert into public.groups (name, currency, color, created_by)
  values (btrim(p_name), upper(btrim(p_currency)), p_color, v_user)
  returning id into v_group;

  insert into public.members (group_id, name, user_id) values (v_group, v_my_name, v_user);
  perform public.apply_account_name(v_user, v_my_name);

  foreach v_name in array coalesce(p_other_names, '{}') loop
    if char_length(btrim(v_name)) > 0 then
      insert into public.members (group_id, name) values (v_group, public.clean_name(v_name));
    end if;
  end loop;

  return query select v_group, null::text, null::jsonb;
end;
$$;

create or replace function public.join_group(hasura_session json, p_code text, p_member_id uuid default null, p_name text default null)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_group uuid;
  v_name text;
begin
  select id into v_group from public.groups where invite_code = upper(btrim(p_code)) for update;
  if not found then
    perform public.fail('invalid_code');
  end if;
  if not public.is_group_member(v_group, v_user) then
    if p_member_id is not null then
      -- Taking over a name someone typed in: its expenses become mine, the name becomes my account name.
      update public.members set user_id = v_user
      where id = p_member_id and group_id = v_group and user_id is null
      returning name into v_name;
      if not found then
        perform public.fail('member_taken');
      end if;
      perform public.apply_account_name(v_user, coalesce(public.account_name(v_user), p_name, v_name));
    else
      v_name := coalesce(public.account_name(v_user), public.clean_name(p_name));
      insert into public.members (group_id, name, user_id) values (v_group, v_name, v_user);
      perform public.apply_account_name(v_user, v_name);
    end if;
  end if;
  return query select v_group, null::text, null::jsonb;
end;
$$;

-- Only names of people without the app can be changed in a group.
create or replace function public.rename_member(hasura_session json, p_member_id uuid, p_name text)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_group uuid;
  v_linked boolean;
begin
  select group_id, user_id is not null into v_group, v_linked from public.members where id = p_member_id;
  if v_group is null then
    perform public.fail('member_not_found');
  end if;
  perform public.require_group_member(v_group, public.session_user_id(hasura_session));
  if v_linked then
    perform public.fail('member_linked');
  end if;
  update public.members set name = public.clean_name(p_name) where id = p_member_id;
end;
$$;

-- Switching to another name in a group is gone: with account names there is nothing to switch.
drop function public.claim_member(json, uuid);

-- Existing accounts: their newest group name becomes the account name, and all groups follow it.
insert into public.profiles (user_id, name)
select distinct on (user_id) user_id, name
from public.members
where user_id is not null
order by user_id, created_at desc
on conflict do nothing;

-- Bookkeeping, not something anyone did: no history entries for it.
alter table public.members disable trigger members_audit;
update public.members m set name = p.name
from public.profiles p
where m.user_id = p.user_id and m.name is distinct from p.name;
alter table public.members enable trigger members_audit;
