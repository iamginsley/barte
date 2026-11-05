-- Payment details: how someone wants to be paid back (PayPal.me name, IBAN and account holder).
-- One row per person, visible to the people they share a group with. Written only through
-- set_payment_details, which normalizes and validates (IBAN checksum included).

create table public.payment_details (
  user_id uuid primary key references auth.users (id) on delete cascade,
  paypal text check (paypal ~ '^[A-Za-z0-9]{1,20}$'),
  iban text check (iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
  account_holder text check (char_length(account_holder) between 1 and 70),
  updated_at timestamptz not null default now()
);

alter table public.payment_details enable row level security;

-- Security definer so the policy can look at members without recursing into its RLS.
create or replace function public.shares_group_with(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.members mine
    join public.members theirs on theirs.group_id = mine.group_id
    where mine.user_id = (select auth.uid()) and theirs.user_id = p_user
  );
$$;

create policy "people in the same group read payment details"
  on public.payment_details for select to authenticated
  using (user_id = (select auth.uid()) or public.shares_group_with(user_id));

create or replace function public.iban_is_valid(p_iban text)
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

create or replace function public.set_payment_details(p_paypal text, p_iban text, p_account_holder text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := public.require_user();
  v_paypal text := nullif(btrim(coalesce(p_paypal, '')), '');
  v_iban text := nullif(upper(regexp_replace(coalesce(p_iban, ''), '[\s-]', '', 'g')), '');
  v_holder text := nullif(btrim(regexp_replace(coalesce(p_account_holder, ''), '\s+', ' ', 'g')), '');
begin
  if v_paypal is not null then
    v_paypal := regexp_replace(v_paypal, '^(https?://)?(www\.)?paypal\.me/', '', 'i');
    v_paypal := split_part(ltrim(v_paypal, '@'), '/', 1);
    if v_paypal !~ '^[A-Za-z0-9]{1,20}$' then
      raise exception 'not a PayPal.me name' using errcode = 'P0001', hint = 'invalid_paypal';
    end if;
  end if;
  if v_iban is not null and not public.iban_is_valid(v_iban) then
    raise exception 'invalid IBAN' using errcode = 'P0001', hint = 'invalid_iban';
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

revoke execute on function public.set_payment_details(text, text, text) from public, anon;
grant execute on function public.set_payment_details(text, text, text) to authenticated;
revoke execute on function public.shares_group_with(uuid) from public, anon;
grant execute on function public.shares_group_with(uuid) to authenticated;

-- Changes reach the others' settle-up screens live.
alter table public.payment_details replica identity full;
alter publication supabase_realtime add table public.payment_details;
