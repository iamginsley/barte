-- History of everything that changes money or names in a group, so nobody can quietly edit or
-- delete an expense. Rows are written by triggers inside the same transaction as the change, so
-- no client can skip them, and they can never be edited or deleted, except together with their
-- group when the whole group is deleted.
--
-- Each new row also fires a Hasura event trigger (nhost/metadata) that calls the group-event
-- function, which sends the push notifications. The app itself no longer triggers pushes.

create table public.group_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  -- expense_added, expense_changed, expense_deleted, settlement_added, settlement_deleted,
  -- group_updated, group_closed, group_reopened, member_added, member_renamed, member_removed
  kind text not null,
  -- Who did it, and their name in the group at that moment (it survives renames and leaving).
  actor_id uuid,
  actor_name text,
  -- The expense or member the event is about. No foreign key: the history outlives deletions.
  subject_id uuid,
  -- The row before and after, as JSON. Null for additions (old) and deletions (new).
  old jsonb,
  new jsonb,
  created_at timestamptz not null default clock_timestamp()
);

create index group_events_group_idx on public.group_events (group_id, created_at desc);
create index group_events_subject_idx on public.group_events (subject_id, created_at desc);

-- Who is acting -------------------------------------------------------------

-- Every API function resolves the caller through this helper, which is why it now also remembers
-- the caller for the rest of the transaction; the history triggers read it from there.
create or replace function public.session_user_id(hasura_session json)
returns uuid
language plpgsql
volatile
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
  perform set_config('barte.actor', v_id::text, true);
  return v_id;
end;
$$;

-- The caller of the current transaction: set by session_user_id, or Hasura's own session for
-- anything that reaches the tables another way. Null for admin changes without a user.
create function public.current_actor()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_actor text := nullif(current_setting('barte.actor', true), '');
begin
  if v_actor is null then
    v_actor := nullif(current_setting('hasura.user', true), '')::json ->> 'x-hasura-user-id';
  end if;
  return v_actor::uuid;
exception when others then
  return null;
end;
$$;

create function public.log_group_event(p_group_id uuid, p_kind text, p_subject uuid, p_old jsonb, p_new jsonb)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_actor uuid := public.current_actor();
begin
  -- The group is being deleted (cascade): its history goes with it.
  if not exists (select 1 from public.groups where id = p_group_id) then
    return;
  end if;
  insert into public.group_events (group_id, kind, actor_id, actor_name, subject_id, old, new)
  values (
    p_group_id, p_kind, v_actor,
    (select name from public.members where group_id = p_group_id and user_id = v_actor),
    p_subject, p_old, p_new
  );
end;
$$;

-- Expenses ------------------------------------------------------------------

-- The parts of an expense that the history shows and compares.
create function public.expense_snapshot(e public.expenses)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'title', e.title,
    'amount_cents', e.amount_cents,
    'spent_on', e.spent_on,
    'payer_id', e.payer_id,
    'participant_ids', to_jsonb(e.participant_ids),
    'is_settlement', e.is_settlement,
    'split_kind', e.split_kind,
    'split_values', to_jsonb(e.split_values)
  );
$$;

create function public.audit_expense()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_prefix text := case when coalesce(new.is_settlement, old.is_settlement) then 'settlement' else 'expense' end;
begin
  if tg_op = 'INSERT' then
    perform public.log_group_event(new.group_id, v_prefix || '_added', new.id, null, public.expense_snapshot(new));
  elsif tg_op = 'DELETE' then
    perform public.log_group_event(old.group_id, v_prefix || '_deleted', old.id, public.expense_snapshot(old), null);
  elsif public.expense_snapshot(old) is distinct from public.expense_snapshot(new) then
    -- Unchanged saves and bookkeeping (created_by after an account deletion) leave no trace.
    perform public.log_group_event(new.group_id, 'expense_changed', new.id, public.expense_snapshot(old), public.expense_snapshot(new));
  end if;
  return null;
end;
$$;

create trigger expenses_audit
after insert or update or delete on public.expenses
for each row execute function public.audit_expense();

-- Groups --------------------------------------------------------------------

create function public.audit_group()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (old.name, old.currency) is distinct from (new.name, new.currency) then
    perform public.log_group_event(new.id, 'group_updated', new.id,
      jsonb_build_object('name', old.name, 'currency', old.currency),
      jsonb_build_object('name', new.name, 'currency', new.currency));
  end if;
  if old.closed_at is null and new.closed_at is not null then
    perform public.log_group_event(new.id, 'group_closed', new.id, null, null);
  elsif old.closed_at is not null and new.closed_at is null then
    perform public.log_group_event(new.id, 'group_reopened', new.id, null, null);
  end if;
  return null;
end;
$$;

create trigger groups_audit
after update on public.groups
for each row execute function public.audit_group();

-- Members -------------------------------------------------------------------

create function public.audit_member()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- The names a group starts with belong to its creation, not to its history.
    if exists (select 1 from public.groups where id = new.group_id and created_at < now()) then
      perform public.log_group_event(new.group_id, 'member_added', new.id, null, jsonb_build_object('name', new.name));
    end if;
  elsif tg_op = 'DELETE' then
    perform public.log_group_event(old.group_id, 'member_removed', old.id, jsonb_build_object('name', old.name), null);
  elsif old.name is distinct from new.name then
    perform public.log_group_event(new.group_id, 'member_renamed', new.id,
      jsonb_build_object('name', old.name), jsonb_build_object('name', new.name));
  end if;
  return null;
end;
$$;

create trigger members_audit
after insert or update or delete on public.members
for each row execute function public.audit_member();

-- Append-only ---------------------------------------------------------------

create function public.protect_group_events()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.groups where id = old.group_id) then
    return old;
  end if;
  raise exception 'group_events are append-only' using errcode = '42501';
end;
$$;

create trigger group_events_append_only
before update or delete on public.group_events
for each row execute function public.protect_group_events();
