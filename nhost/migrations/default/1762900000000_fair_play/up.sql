-- Fair play, like Splitwise: nobody can make debts disappear.
--   1. No group can be deleted. Everyone can only leave; the last person with Barte takes the
--      group with them (leave_group, delete_my_account), so nothing is left that nobody can see.
--   2. Leaving needs a settled balance while others with Barte are still in the group.
--   3. Closing needs everyone settled, so open amounts can't vanish from the overview and widget.
--   4. Joining is logged as its own history entry (and pushed to the group), above all when someone
--      takes over a name that was typed in: its expenses become theirs. Leaving is logged too.
-- Deleted expenses can be restored by anyone in the group: the app saves the history's snapshot
-- again with the same id through save_expense.

-- 1 -------------------------------------------------------------------------------

drop function public.delete_group(json, uuid);

-- 2 and 3: balances -----------------------------------------------------------------

-- Each member's balance in exact cents (paid minus their share, without rounding) and how many of
-- their shares the app rounds to whole cents. The app's balance (Ledger.swift) differs from the
-- exact one by less than one cent per rounded share, so a member counts as settled when the exact
-- balance is within that margin. Fixed amounts ('exact') are never rounded.
create function public.member_balances(p_group_id uuid)
returns table (member_id uuid, balance numeric, rounded_shares integer)
language sql
stable
set search_path = ''
as $$
  with e as (
    select * from public.expenses where group_id = p_group_id
  ), shares as (
    select p.member_id,
      case e.split_kind
        when 'exact' then e.split_values[p.ord]::numeric
        when 'shares' then e.amount_cents::numeric * e.split_values[p.ord]
          / (select sum(v) from unnest(e.split_values) as v)
        else e.amount_cents::numeric / cardinality(e.participant_ids)
      end as share,
      e.split_kind <> 'exact' as rounded
    from e, unnest(e.participant_ids) with ordinality as p(member_id, ord)
  )
  select m.id,
    coalesce((select sum(e.amount_cents) from e where e.payer_id = m.id), 0)
      - coalesce((select sum(s.share) from shares s where s.member_id = m.id), 0),
    (select count(*) from shares s where s.member_id = m.id and s.rounded)::integer
  from public.members m
  where m.group_id = p_group_id;
$$;

create function public.is_settled(p_group_id uuid, p_member_id uuid default null)
returns boolean
language sql
stable
set search_path = ''
as $$
  select not exists (
    select 1 from public.member_balances(p_group_id) b
    where (p_member_id is null or b.member_id = p_member_id)
      and abs(b.balance) >= greatest(b.rounded_shares, 1)
  );
$$;

create or replace function public.leave_group(hasura_session json, p_group_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_member uuid;
begin
  perform public.require_group_member(p_group_id, v_user);
  select id into v_member from public.members where group_id = p_group_id and user_id = v_user;
  -- Nobody walks away from a debt (or a claim) while others with Barte are still in the group.
  if exists (select 1 from public.members where group_id = p_group_id and user_id is not null and user_id <> v_user)
     and not public.is_settled(p_group_id, v_member) then
    perform public.fail('open_balance');
  end if;
  update public.members set user_id = null where id = v_member;
  if not exists (select 1 from public.members where group_id = p_group_id and user_id is not null) then
    delete from public.groups where id = p_group_id;
  end if;
end;
$$;

create or replace function public.set_group_closed(hasura_session json, p_group_id uuid, p_closed boolean)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
begin
  perform public.require_group_member(p_group_id, public.session_user_id(hasura_session));
  if p_closed
     and exists (select 1 from public.groups where id = p_group_id and closed_at is null)
     and not public.is_settled(p_group_id) then
    perform public.fail('open_balances');
  end if;
  update public.groups
  set closed_at = case when p_closed then coalesce(closed_at, now()) end
  where id = p_group_id;
end;
$$;

-- 4 -------------------------------------------------------------------------------

-- Taking over a name sets the account and its name in one step, so the history shows one entry:
-- who joined, and which name (with its expenses) they took over.
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
      select coalesce(public.account_name(v_user), nullif(btrim(coalesce(p_name, '')), ''), m.name) into v_name
      from public.members m
      where m.id = p_member_id and m.group_id = v_group and m.user_id is null
      for update;
      if v_name is null then
        perform public.fail('member_taken');
      end if;
      v_name := public.clean_name(v_name);
      update public.members set user_id = v_user, name = v_name where id = p_member_id;
      perform public.apply_account_name(v_user, v_name);
    else
      v_name := coalesce(public.account_name(v_user), public.clean_name(p_name));
      insert into public.members (group_id, name, user_id) values (v_group, v_name, v_user);
      perform public.apply_account_name(v_user, v_name);
    end if;
  end if;
  return query select v_group, null::text, null::jsonb;
end;
$$;

create or replace function public.audit_member()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- The names a group starts with belong to its creation, not to its history.
    if exists (select 1 from public.groups where id = new.group_id and created_at < now()) then
      perform public.log_group_event(new.group_id,
        case when new.user_id is null then 'member_added' else 'member_joined' end,
        new.id, null, jsonb_build_object('name', new.name));
    end if;
  elsif tg_op = 'DELETE' then
    perform public.log_group_event(old.group_id, 'member_removed', old.id, jsonb_build_object('name', old.name), null);
  elsif old.user_id is null and new.user_id is not null then
    -- Took over a typed-in name: old has the name as it was, new the account name.
    perform public.log_group_event(new.group_id, 'member_joined', new.id,
      jsonb_build_object('name', old.name), jsonb_build_object('name', new.name));
  elsif old.user_id is not null and new.user_id is null then
    perform public.log_group_event(new.group_id, 'member_left', new.id, jsonb_build_object('name', old.name), null);
  elsif old.name is distinct from new.name then
    perform public.log_group_event(new.group_id, 'member_renamed', new.id,
      jsonb_build_object('name', old.name), jsonb_build_object('name', new.name));
  end if;
  return null;
end;
$$;
