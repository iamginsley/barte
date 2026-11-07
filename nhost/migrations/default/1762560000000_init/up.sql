-- Barte: groups, their members and expenses, payment details and push devices.
--
-- Members are names. A member can be linked to a signed-in person (user_id), which is how that
-- person sees the group and which member is "me" for them. Friends without the app stay plain names.
--
-- The app reads through Hasura with the `user` role; the select permissions in nhost/metadata keep
-- everyone to their own groups. Every write goes through the functions below, which Hasura exposes
-- as mutations. Hasura passes the caller's session (from the Nhost JWT) as `hasura_session`, and the
-- functions check membership themselves. Errors are raised with SQLSTATE 22000 and the hint as the
-- message, because Hasura passes data exceptions on to the app as they are.

-- Return type ---------------------------------------------------------------

-- Hasura exposes functions only when they return rows of a tracked table. This one never holds a
-- row (check (false)); it is the shape every API function returns: an id, an invite code or a preview.
create table public.api_results (
  id uuid,
  code text,
  preview jsonb,
  constraint api_results_never_stored check (false)
);

-- Tables --------------------------------------------------------------------

-- Eight characters without look-alikes (0/O, 1/I/L), so codes can also be typed in by hand.
create function public.generate_invite_code()
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
  created_by uuid references auth.users (id) on delete set null,
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
  -- Unequal splits: by shares (a couple counts twice) or with a fixed amount per person.
  -- split_values lines up with participant_ids: weights for 'shares', cents for 'exact'.
  -- The app computes the actual shares (Ledger.swift), so every device agrees.
  split_kind text not null default 'equal' check (split_kind in ('equal', 'shares', 'exact')),
  split_values bigint[],
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expenses_split_values_match check (
    case split_kind
      when 'equal' then split_values is null
      else split_values is not null and cardinality(split_values) = cardinality(participant_ids)
    end
  )
);

create index expenses_group_idx on public.expenses (group_id, spent_on desc);

-- How someone wants to be paid back (PayPal.me name, IBAN and account holder). One row per person,
-- visible to the people they share a group with.
create table public.payment_details (
  user_id uuid primary key references auth.users (id) on delete cascade,
  paypal text check (paypal ~ '^[A-Za-z0-9]{1,20}$'),
  iban text check (iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
  account_holder text check (char_length(account_holder) between 1 and 70),
  updated_at timestamptz not null default now()
);

-- Push notifications: one row per device. Only the notify function reads these, with the admin role.
create table public.device_tokens (
  token text primary key check (token ~ '^[0-9a-f]{64,200}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_id_idx on public.device_tokens (user_id);

-- Helpers -------------------------------------------------------------------

create function public.fail(p_hint text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception '%', p_hint using errcode = '22000';
end;
$$;

-- The signed-in person, from the session Hasura passes in.
create function public.session_user_id(hasura_session json)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_id uuid;
begin
  begin
    v_id := nullif(hasura_session ->> 'x-hasura-user-id', '')::uuid;
  exception when invalid_text_representation then
    v_id := null;
  end;
  if v_id is null then
    perform public.fail('not_signed_in');
  end if;
  return v_id;
end;
$$;

create function public.is_group_member(p_group_id uuid, p_user uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.members m
    where m.group_id = p_group_id and m.user_id = p_user
  );
$$;

create function public.require_group_member(p_group_id uuid, p_user uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not public.is_group_member(p_group_id, p_user) then
    perform public.fail('not_member');
  end if;
end;
$$;

create function public.clean_name(p_name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := btrim(coalesce(p_name, ''));
begin
  if char_length(v) = 0 then
    perform public.fail('empty_name');
  end if;
  return left(v, 40);
end;
$$;

create function public.iban_is_valid(p_iban text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rearranged text;
  v_char text;
  v_remainder int := 0;
begin
  if p_iban is null or p_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then
    return false;
  end if;
  v_rearranged := substr(p_iban, 5) || substr(p_iban, 1, 4);
  for i in 1..char_length(v_rearranged) loop
    v_char := substr(v_rearranged, i, 1);
    if v_char ~ '[0-9]' then
      v_remainder := (v_remainder * 10 + v_char::int) % 97;
    else
      v_remainder := (v_remainder * 100 + ascii(v_char) - 55) % 97;
    end if;
  end loop;
  return v_remainder = 1;
end;
$$;

-- Groups --------------------------------------------------------------------

-- Creates a group with me as the first member (linked) and the others as plain names.
create function public.create_group(
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

  return query select v_group, null::text, null::jsonb;
end;
$$;

create function public.update_group(hasura_session json, p_group_id uuid, p_name text, p_currency text, p_color smallint)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
begin
  perform public.require_group_member(p_group_id, public.session_user_id(hasura_session));
  update public.groups
  set name = btrim(p_name), currency = upper(btrim(p_currency)), color = p_color
  where id = p_group_id;
end;
$$;

-- The creator deletes a group for everyone. Others can only leave (see leave_group),
-- unless nobody else in it uses the app any more.
create function public.delete_group(hasura_session json, p_group_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
begin
  perform public.require_group_member(p_group_id, v_user);
  if not exists (
    select 1 from public.groups g where g.id = p_group_id
    and (g.created_by = v_user or not exists (
      select 1 from public.members m where m.group_id = g.id and m.user_id is not null and m.user_id <> v_user
    ))
  ) then
    perform public.fail('not_creator');
  end if;
  delete from public.groups where id = p_group_id;
end;
$$;

-- Unlinks me from my member; the name and its expenses stay for the others.
-- The last person with the app takes the group with them.
create function public.leave_group(hasura_session json, p_group_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
begin
  perform public.require_group_member(p_group_id, v_user);
  update public.members set user_id = null where group_id = p_group_id and user_id = v_user;
  if not exists (select 1 from public.members where group_id = p_group_id and user_id is not null) then
    delete from public.groups where id = p_group_id;
  end if;
end;
$$;

create function public.regenerate_invite_code(hasura_session json, p_group_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_code text;
begin
  perform public.require_group_member(p_group_id, public.session_user_id(hasura_session));
  update public.groups set invite_code = public.generate_invite_code()
  where id = p_group_id
  returning invite_code into v_code;
  return query select null::uuid, v_code, null::jsonb;
end;
$$;

-- Joining -------------------------------------------------------------------

-- What someone with an invite code sees before joining: the group and who is still unclaimed.
-- Volatile only so Hasura exposes it as a mutation like the others (it changes nothing).
create function public.preview_invite(hasura_session json, p_code text)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_group public.groups;
begin
  select * into v_group from public.groups where invite_code = upper(btrim(p_code));
  if not found then
    perform public.fail('invalid_code');
  end if;
  return query select v_group.id, null::text, jsonb_build_object(
    'group_id', v_group.id,
    'name', v_group.name,
    'currency', v_group.currency,
    'color', v_group.color,
    'is_member', public.is_group_member(v_group.id, v_user),
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
create function public.join_group(hasura_session json, p_code text, p_member_id uuid default null, p_name text default null)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_group uuid;
begin
  select id into v_group from public.groups where invite_code = upper(btrim(p_code)) for update;
  if not found then
    perform public.fail('invalid_code');
  end if;
  if not public.is_group_member(v_group, v_user) then
    if p_member_id is not null then
      update public.members set user_id = v_user
      where id = p_member_id and group_id = v_group and user_id is null;
      if not found then
        perform public.fail('member_taken');
      end if;
    else
      insert into public.members (group_id, name, user_id) values (v_group, public.clean_name(p_name), v_user);
    end if;
  end if;
  return query select v_group, null::text, null::jsonb;
end;
$$;

-- "That's not me": switches which name I am in a group I already belong to.
create function public.claim_member(hasura_session json, p_member_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_group uuid;
begin
  select group_id into v_group from public.members where id = p_member_id;
  if v_group is null then
    perform public.fail('member_not_found');
  end if;
  perform public.require_group_member(v_group, v_user);
  if exists (select 1 from public.members where id = p_member_id and user_id = v_user) then
    return;
  end if;
  if exists (select 1 from public.members where id = p_member_id and user_id is not null) then
    perform public.fail('member_taken');
  end if;
  update public.members set user_id = null where group_id = v_group and user_id = v_user;
  update public.members set user_id = v_user where id = p_member_id;
end;
$$;

-- Members -------------------------------------------------------------------

create function public.add_member(hasura_session json, p_group_id uuid, p_name text)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform public.require_group_member(p_group_id, public.session_user_id(hasura_session));
  insert into public.members (group_id, name) values (p_group_id, public.clean_name(p_name))
  returning id into v_id;
  return query select v_id, null::text, null::jsonb;
end;
$$;

create function public.rename_member(hasura_session json, p_member_id uuid, p_name text)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from public.members where id = p_member_id;
  if v_group is null then
    perform public.fail('member_not_found');
  end if;
  perform public.require_group_member(v_group, public.session_user_id(hasura_session));
  update public.members set name = public.clean_name(p_name) where id = p_member_id;
end;
$$;

-- Only names that appear in no expense and aren't someone with the app can be removed.
create function public.remove_member(hasura_session json, p_member_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_member public.members;
begin
  select * into v_member from public.members where id = p_member_id;
  if not found then
    return;
  end if;
  perform public.require_group_member(v_member.group_id, v_user);
  if v_member.user_id is not null then
    perform public.fail('member_linked');
  end if;
  if exists (
    select 1 from public.expenses e
    where e.group_id = v_member.group_id and (e.payer_id = p_member_id or p_member_id = any (e.participant_ids))
  ) then
    perform public.fail('member_involved');
  end if;
  delete from public.members where id = p_member_id;
end;
$$;

-- Expenses ------------------------------------------------------------------

-- Inserts or updates an expense. The id comes from the app so a retry never creates a duplicate.
create function public.save_expense(
  hasura_session json,
  p_id uuid,
  p_group_id uuid,
  p_title text,
  p_amount_cents bigint,
  p_spent_on date,
  p_payer_id uuid,
  p_participant_ids uuid[],
  p_is_settlement boolean default false,
  p_split_kind text default 'equal',
  p_split_values bigint[] default null
)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_participants uuid[];
  v_kind text := coalesce(p_split_kind, 'equal');
  v_values bigint[];
begin
  perform public.require_group_member(p_group_id, v_user);

  if v_kind = 'equal' then
    select coalesce(array_agg(distinct p), '{}') into v_participants from unnest(p_participant_ids) as p;
    v_values := null;
  elsif v_kind in ('shares', 'exact') then
    -- Values line up with participants, so the order has to stay as sent.
    v_participants := coalesce(p_participant_ids, '{}');
    v_values := p_split_values;
    if v_values is null
       or cardinality(v_values) <> cardinality(v_participants)
       or (select count(distinct p) from unnest(v_participants) as p) <> cardinality(v_participants)
       or exists (select 1 from unnest(v_values) as v where v is null or v <= 0)
       or (v_kind = 'shares' and exists (select 1 from unnest(v_values) as v where v > 100))
       or (v_kind = 'exact' and (select sum(v) from unnest(v_values) as v) <> p_amount_cents) then
      perform public.fail('invalid_split');
    end if;
  else
    perform public.fail('invalid_split');
  end if;

  if cardinality(v_participants) = 0 then
    perform public.fail('no_participants');
  end if;
  if not exists (select 1 from public.members where id = p_payer_id and group_id = p_group_id)
     or exists (
       select 1 from unnest(v_participants) as p
       where not exists (select 1 from public.members m where m.id = p and m.group_id = p_group_id)
     ) then
    perform public.fail('unknown_member');
  end if;
  if p_is_settlement and (v_kind <> 'equal' or cardinality(v_participants) <> 1 or v_participants[1] = p_payer_id) then
    perform public.fail('invalid_settlement');
  end if;
  if exists (select 1 from public.expenses where id = p_id and group_id <> p_group_id) then
    perform public.fail('not_member');
  end if;

  insert into public.expenses (id, group_id, title, amount_cents, spent_on, payer_id, participant_ids, is_settlement, split_kind, split_values, created_by)
  values (p_id, p_group_id, btrim(p_title), p_amount_cents, p_spent_on, p_payer_id, v_participants, p_is_settlement, v_kind, v_values, v_user)
  on conflict (id) do update set
    title = excluded.title,
    amount_cents = excluded.amount_cents,
    spent_on = excluded.spent_on,
    payer_id = excluded.payer_id,
    participant_ids = excluded.participant_ids,
    is_settlement = excluded.is_settlement,
    split_kind = excluded.split_kind,
    split_values = excluded.split_values,
    updated_at = now();
  return query select p_id, null::text, null::jsonb;
end;
$$;

create function public.delete_expense(hasura_session json, p_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from public.expenses where id = p_id;
  if v_group is null then
    return;
  end if;
  perform public.require_group_member(v_group, public.session_user_id(hasura_session));
  delete from public.expenses where id = p_id;
end;
$$;

-- Payment details -----------------------------------------------------------

-- Normalizes and validates (IBAN checksum included). Empty details remove the row.
create function public.set_payment_details(hasura_session json, p_paypal text, p_iban text, p_account_holder text)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  v_paypal text := nullif(btrim(coalesce(p_paypal, '')), '');
  v_iban text := nullif(upper(regexp_replace(coalesce(p_iban, ''), '[\s-]', '', 'g')), '');
  v_holder text := nullif(btrim(regexp_replace(coalesce(p_account_holder, ''), '\s+', ' ', 'g')), '');
begin
  if v_paypal is not null then
    v_paypal := regexp_replace(v_paypal, '^(https?://)?(www\.)?paypal\.me/', '', 'i');
    v_paypal := split_part(ltrim(v_paypal, '@'), '/', 1);
    if v_paypal !~ '^[A-Za-z0-9]{1,20}$' then
      perform public.fail('invalid_paypal');
    end if;
  end if;
  if v_iban is not null and not public.iban_is_valid(v_iban) then
    perform public.fail('invalid_iban');
  end if;
  if v_iban is null then
    v_holder := null;
  end if;

  if v_paypal is null and v_iban is null then
    delete from public.payment_details where user_id = v_user;
    return;
  end if;

  insert into public.payment_details (user_id, paypal, iban, account_holder)
  values (v_user, v_paypal, v_iban, left(v_holder, 70))
  on conflict (user_id) do update set
    paypal = excluded.paypal,
    iban = excluded.iban,
    account_holder = excluded.account_holder,
    updated_at = now();
end;
$$;

-- Push devices --------------------------------------------------------------

-- A phone can change hands (sign out, other person signs in), so registering moves the token
-- to the caller instead of failing on someone else's row.
create function public.register_device(hasura_session json, p_token text, p_environment text)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
begin
  insert into public.device_tokens (token, user_id, environment)
  values (lower(p_token), public.session_user_id(hasura_session), p_environment)
  on conflict (token) do update
    set user_id = excluded.user_id, environment = excluded.environment, updated_at = now();
end;
$$;

-- Before signing out, so the next person on this phone doesn't get the previous one's notifications.
create function public.unregister_device(hasura_session json, p_token text)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
begin
  delete from public.device_tokens
  where token = lower(p_token) and user_id = public.session_user_id(hasura_session);
end;
$$;

-- Account -------------------------------------------------------------------

-- In-app account deletion (App Store Review Guideline 5.1.1(v)). The app revokes the Sign in with
-- Apple link first (apple-revoke function), then calls this.
--
-- Deleting the auth user unlinks the person from every group (members.user_id is set null),
-- so friends keep the shared history with the name. Groups in which nobody else uses the app
-- are deleted first, because nobody could open them afterwards. Sessions, payment details and
-- devices go with the user.
create function public.delete_my_account(hasura_session json)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
begin
  delete from public.groups g
  where exists (select 1 from public.members m where m.group_id = g.id and m.user_id = v_user)
    and not exists (
      select 1 from public.members m where m.group_id = g.id and m.user_id is not null and m.user_id <> v_user
    );

  delete from auth.users where id = v_user;
end;
$$;
