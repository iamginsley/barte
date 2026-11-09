-- Reminders: whoever is owed money can nudge someone who owes them, at most once a day per person.
-- The push goes only to that person (event trigger reminder_notify → events/reminder) and stays out
-- of the group history and chat, so nobody is shown up in front of the group. The amount is checked
-- against the balances, so a reminder can't ask for more than is actually open.

create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  from_member uuid not null references public.members (id) on delete cascade,
  to_member uuid not null references public.members (id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  created_at timestamptz not null default now()
);

create index reminders_recent on public.reminders (from_member, to_member, created_at desc);

create function public.remind(hasura_session json, p_group_id uuid, p_member_id uuid, p_amount_cents integer)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_from uuid;
  v_target public.members;
  v_owed numeric;
  v_owes numeric;
  v_margin integer;
begin
  perform public.require_group_member(p_group_id, v_user);
  select id into v_from from public.members where group_id = p_group_id and user_id = v_user;
  select * into v_target from public.members where id = p_member_id and group_id = p_group_id;
  if v_target.id is null or v_target.id = v_from then
    perform public.fail('not_member');
  end if;
  -- Typed-in names have no phone to remind; the app offers a message to share instead.
  if v_target.user_id is null then
    perform public.fail('no_app');
  end if;

  select balance into v_owed from public.member_balances(p_group_id) where member_id = v_from;
  select -balance, greatest(rounded_shares, 1) into v_owes, v_margin
  from public.member_balances(p_group_id) where member_id = p_member_id;
  if v_owed < 1 or v_owes < v_margin then
    perform public.fail('nothing_owed');
  end if;
  -- The app suggests the transfer from the settle-up plan; it can't exceed what either side has open.
  if p_amount_cents is null or p_amount_cents < 1 or p_amount_cents > least(v_owed, v_owes) + v_margin then
    perform public.fail('invalid_amount');
  end if;

  if exists (
    select 1 from public.reminders
    where from_member = v_from and to_member = p_member_id and created_at > now() - interval '20 hours'
  ) then
    perform public.fail('reminded_recently');
  end if;

  -- Old reminders only served the daily limit.
  delete from public.reminders where created_at < now() - interval '7 days';
  insert into public.reminders (group_id, from_member, to_member, amount_cents)
  values (p_group_id, v_from, p_member_id, p_amount_cents);
end;
$$;
