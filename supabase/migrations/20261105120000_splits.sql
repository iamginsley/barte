-- Unequal splits: by shares (a couple counts twice) or with a fixed amount per person.
-- split_values lines up with participant_ids: weights for 'shares', cents for 'exact'.
-- The app computes the actual shares (Ledger.swift), so every device agrees.

alter table public.expenses
  add column split_kind text not null default 'equal' check (split_kind in ('equal', 'shares', 'exact')),
  add column split_values bigint[],
  add constraint expenses_split_values_match check (
    case split_kind
      when 'equal' then split_values is null
      else split_values is not null and cardinality(split_values) = cardinality(participant_ids)
    end
  );

drop function public.save_expense(uuid, uuid, text, bigint, date, uuid, uuid[], boolean);

create function public.save_expense(
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
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participants uuid[];
  v_kind text := coalesce(p_split_kind, 'equal');
  v_values bigint[];
begin
  perform public.require_group_member(p_group_id);

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
      raise exception 'split does not add up' using errcode = 'P0001', hint = 'invalid_split';
    end if;
  else
    raise exception 'unknown split' using errcode = 'P0001', hint = 'invalid_split';
  end if;

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
  if p_is_settlement and (v_kind <> 'equal' or cardinality(v_participants) <> 1 or v_participants[1] = p_payer_id) then
    raise exception 'a settlement goes from one person to another' using errcode = 'P0001', hint = 'invalid_settlement';
  end if;
  if exists (select 1 from public.expenses where id = p_id and group_id <> p_group_id) then
    raise exception 'expense belongs to another group' using errcode = '42501', hint = 'not_member';
  end if;

  insert into public.expenses (id, group_id, title, amount_cents, spent_on, payer_id, participant_ids, is_settlement, split_kind, split_values)
  values (p_id, p_group_id, btrim(p_title), p_amount_cents, p_spent_on, p_payer_id, v_participants, p_is_settlement, v_kind, v_values)
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
end;
$$;

revoke execute on function public.save_expense(uuid, uuid, text, bigint, date, uuid, uuid[], boolean, text, bigint[]) from public, anon;
grant execute on function public.save_expense(uuid, uuid, text, bigint, date, uuid, uuid[], boolean, text, bigint[]) to authenticated;
