-- Barte: groups, their members and expenses.
--
-- Members are names. A member can be linked to a signed-in person (user_id), which is how that
-- person sees the group and which member is "me" for them. Friends without the app stay plain names.
-- Clients only read through RLS; every write goes through the security definer functions below,
-- which check membership and keep expenses consistent with the group's members.

create extension if not exists pgcrypto with schema extensions;

-- Eight characters without look-alikes (0/O, 1/I/L), so codes can also be typed in by hand.
create or replace function public.generate_invite_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', (floor(random() * 31) + 1)::int, 1), '')
  from generate_series(1, 8);
$$;

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  currency text not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  -- Index into the app's card colors; the app keeps the order stable.
  color smallint not null default 0 check (color between 0 and 31),
  invite_code text not null unique default public.generate_invite_code(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 40),
  -- Deleting an account turns the person back into a plain name; their history stays.
  user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (group_id, user_id)
);

create index members_group_idx on public.members (group_id);
create index members_user_idx on public.members (user_id) where user_id is not null;

create table public.expenses (
  id uuid primary key,
  group_id uuid not null references public.groups (id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  amount_cents bigint not null check (amount_cents > 0 and amount_cents < 100000000000),
  -- Wall-clock day on the phone that entered it; "today" comes from the device.
  spent_on date not null,
  payer_id uuid not null references public.members (id),
  participant_ids uuid[] not null check (cardinality(participant_ids) between 1 and 100),
  is_settlement boolean not null default false,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index expenses_group_idx on public.expenses (group_id, spent_on desc);

-- Security definer so policies can call it without recursing into RLS on members.
create or replace function public.is_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.members m
    where m.group_id = p_group_id and m.user_id = auth.uid()
  );
$$;

alter table public.groups enable row level security;
alter table public.members enable row level security;
alter table public.expenses enable row level security;

create policy "members read their groups"
  on public.groups for select to authenticated
  using (public.is_group_member(id));

create policy "members read the people in their groups"
  on public.members for select to authenticated
  using (public.is_group_member(group_id));

create policy "members read their groups' expenses"
  on public.expenses for select to authenticated
  using (public.is_group_member(group_id));

-- No insert/update/delete policies: writes only through the functions below.

-- Helpers -------------------------------------------------------------------

create or replace function public.require_user()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  return auth.uid();
end;
$$;

create or replace function public.require_group_member(p_group_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_user();
  if not public.is_group_member(p_group_id) then
    raise exception 'not a member of this group' using errcode = '42501', hint = 'not_member';
  end if;
end;
$$;

create or replace function public.clean_name(p_name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := btrim(coalesce(p_name, ''));
begin
  if char_length(v) = 0 then
    raise exception 'name is empty' using errcode = 'P0001', hint = 'empty_name';
  end if;
  return left(v, 40);
end;
$$;

-- Groups --------------------------------------------------------------------

-- Creates a group with me as the first member (linked) and the others as plain names.
create or replace function public.create_group(
  p_name text,
  p_currency text,
  p_color smallint,
  p_my_name text,
  p_other_names text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := public.require_user();
  v_group uuid;
  v_name text;
begin
  insert into public.groups (name, currency, color, created_by)
  values (btrim(p_name), upper(btrim(p_currency)), p_color, v_user)
  returning id into v_group;

  insert into public.members (group_id, name, user_id)
  values (v_group, public.clean_name(p_my_name), v_user);

  foreach v_name in array coalesce(p_other_names, '{}') loop
    if char_length(btrim(v_name)) > 0 then
      insert into public.members (group_id, name) values (v_group, public.clean_name(v_name));
    end if;
  end loop;

  return v_group;
end;
$$;

create or replace function public.update_group(p_group_id uuid, p_name text, p_currency text, p_color smallint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.require_group_member(p_group_id);
  update public.groups
  set name = btrim(p_name), currency = upper(btrim(p_currency)), color = p_color
  where id = p_group_id;
end;
$$;

-- The creator deletes a group for everyone. Others can only leave (see leave_group),
-- unless nobody else in it uses the app any more.
create or replace function public.delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := public.require_user();
begin
  perform public.require_group_member(p_group_id);
  if not exists (
    select 1 from public.groups g where g.id = p_group_id
    and (g.created_by = v_user or not exists (
      select 1 from public.members m where m.group_id = g.id and m.user_id is not null and m.user_id <> v_user
    ))
  ) then
    raise exception 'only the creator can delete this group' using errcode = '42501', hint = 'not_creator';
  end if;
  delete from public.groups where id = p_group_id;
end;
$$;

-- Unlinks me from my member; the name and its expenses stay for the others.
-- The last person with the app takes the group with them.
create or replace function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := public.require_user();
begin
  perform public.require_group_member(p_group_id);
  update public.members set user_id = null where group_id = p_group_id and user_id = v_user;
  if not exists (select 1 from public.members where group_id = p_group_id and user_id is not null) then
    delete from public.groups where id = p_group_id;
  end if;
end;
$$;

create or replace function public.regenerate_invite_code(p_group_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  perform public.require_group_member(p_group_id);
  update public.groups set invite_code = public.generate_invite_code()
  where id = p_group_id
  returning invite_code into v_code;
  return v_code;
end;
$$;

-- Joining -------------------------------------------------------------------

-- What someone with an invite code sees before joining: the group and who is still unclaimed.
create or replace function public.preview_invite(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group public.groups;
begin
  perform public.require_user();
  select * into v_group from public.groups where invite_code = upper(btrim(p_code));
  if not found then
    raise exception 'invite code not found' using errcode = 'P0001', hint = 'invalid_code';
  end if;
  return jsonb_build_object(
    'group_id', v_group.id,
    'name', v_group.name,
    'currency', v_group.currency,
    'color', v_group.color,
    'is_member', public.is_group_member(v_group.id),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'is_claimed', m.user_id is not null)
                       order by m.created_at, m.id)
      from public.members m where m.group_id = v_group.id
    ), '[]'::jsonb)
  );
end;
$$;

-- Joins with an invite code, either as an existing unclaimed name (p_member_id)
-- or as a new person (p_name). Joining a group I'm already in just returns it.
create or replace function public.join_group(p_code text, p_member_id uuid default null, p_name text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := public.require_user();
  v_group uuid;
begin
  select id into v_group from public.groups where invite_code = upper(btrim(p_code)) for update;
  if not found then
    raise exception 'invite code not found' using errcode = 'P0001', hint = 'invalid_code';
  end if;
  if public.is_group_member(v_group) then
    return v_group;
  end if;

  if p_member_id is not null then
    update public.members set user_id = v_user
    where id = p_member_id and group_id = v_group and user_id is null;
    if not found then
      raise exception 'member already taken' using errcode = 'P0001', hint = 'member_taken';
    end if;
  else
    insert into public.members (group_id, name, user_id) values (v_group, public.clean_name(p_name), v_user);
  end if;
  return v_group;
end;
$$;

-- "That's not me": switches which name I am in a group I already belong to.
create or replace function public.claim_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := public.require_user();
  v_group uuid;
begin
  select group_id into v_group from public.members where id = p_member_id;
  if v_group is null then
    raise exception 'member not found' using errcode = 'P0001', hint = 'member_not_found';
  end if;
  perform public.require_group_member(v_group);
  if exists (select 1 from public.members where id = p_member_id and user_id = v_user) then
    return;
  end if;
  if exists (select 1 from public.members where id = p_member_id and user_id is not null) then
    raise exception 'member already taken' using errcode = 'P0001', hint = 'member_taken';
  end if;
  update public.members set user_id = null where group_id = v_group and user_id = v_user;
  update public.members set user_id = v_user where id = p_member_id;
end;
$$;

-- Members -------------------------------------------------------------------

create or replace function public.add_member(p_group_id uuid, p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform public.require_group_member(p_group_id);
  insert into public.members (group_id, name) values (p_group_id, public.clean_name(p_name))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.rename_member(p_member_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from public.members where id = p_member_id;
  if v_group is null then
    raise exception 'member not found' using errcode = 'P0001', hint = 'member_not_found';
  end if;
  perform public.require_group_member(v_group);
  update public.members set name = public.clean_name(p_name) where id = p_member_id;
end;
$$;

-- Only names that appear in no expense and aren't someone with the app can be removed.
create or replace function public.remove_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.members;
begin
  select * into v_member from public.members where id = p_member_id;
  if not found then
    return;
  end if;
  perform public.require_group_member(v_member.group_id);
  if v_member.user_id is not null then
    raise exception 'member uses the app' using errcode = 'P0001', hint = 'member_linked';
  end if;
  if exists (
    select 1 from public.expenses e
    where e.group_id = v_member.group_id and (e.payer_id = p_member_id or p_member_id = any (e.participant_ids))
  ) then
    raise exception 'member appears in expenses' using errcode = 'P0001', hint = 'member_involved';
  end if;
  delete from public.members where id = p_member_id;
end;
$$;

-- Expenses ------------------------------------------------------------------

-- Inserts or updates an expense. The id comes from the app so a retry never creates a duplicate.
create or replace function public.save_expense(
  p_id uuid,
  p_group_id uuid,
  p_title text,
  p_amount_cents bigint,
  p_spent_on date,
  p_payer_id uuid,
  p_participant_ids uuid[],
  p_is_settlement boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participants uuid[];
begin
  perform public.require_group_member(p_group_id);

  select coalesce(array_agg(distinct p), '{}') into v_participants from unnest(p_participant_ids) as p;
  if cardinality(v_participants) = 0 then
    raise exception 'nobody shares this expense' using errcode = 'P0001', hint = 'no_participants';
  end if;
  if not exists (select 1 from public.members where id = p_payer_id and group_id = p_group_id)
     or exists (
       select 1 from unnest(v_participants) as p
       where not exists (select 1 from public.members m where m.id = p and m.group_id = p_group_id)
     ) then
    raise exception 'people are not in this group' using errcode = 'P0001', hint = 'unknown_member';
  end if;
  if p_is_settlement and (cardinality(v_participants) <> 1 or v_participants[1] = p_payer_id) then
    raise exception 'a settlement goes from one person to another' using errcode = 'P0001', hint = 'invalid_settlement';
  end if;
  if exists (select 1 from public.expenses where id = p_id and group_id <> p_group_id) then
    raise exception 'expense belongs to another group' using errcode = '42501', hint = 'not_member';
  end if;

  insert into public.expenses (id, group_id, title, amount_cents, spent_on, payer_id, participant_ids, is_settlement)
  values (p_id, p_group_id, btrim(p_title), p_amount_cents, p_spent_on, p_payer_id, v_participants, p_is_settlement)
  on conflict (id) do update set
    title = excluded.title,
    amount_cents = excluded.amount_cents,
    spent_on = excluded.spent_on,
    payer_id = excluded.payer_id,
    participant_ids = excluded.participant_ids,
    is_settlement = excluded.is_settlement,
    updated_at = now();
end;
$$;

create or replace function public.delete_expense(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from public.expenses where id = p_id;
  if v_group is null then
    return;
  end if;
  perform public.require_group_member(v_group);
  delete from public.expenses where id = p_id;
end;
$$;

-- Grants --------------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.create_group(text, text, smallint, text, text[])',
    'public.update_group(uuid, text, text, smallint)',
    'public.delete_group(uuid)',
    'public.leave_group(uuid)',
    'public.regenerate_invite_code(uuid)',
    'public.preview_invite(text)',
    'public.join_group(text, uuid, text)',
    'public.claim_member(uuid)',
    'public.add_member(uuid, text)',
    'public.rename_member(uuid, text)',
    'public.remove_member(uuid)',
    'public.save_expense(uuid, uuid, text, bigint, date, uuid, uuid[], boolean)',
    'public.delete_expense(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- Internal helpers are not part of the API.
revoke execute on function public.require_group_member(uuid) from public, anon, authenticated;
revoke execute on function public.generate_invite_code() from public, anon, authenticated;

-- Realtime: the app refetches when anything in its groups changes.
alter table public.members replica identity full;
alter table public.expenses replica identity full;
alter publication supabase_realtime add table public.groups, public.members, public.expenses;
