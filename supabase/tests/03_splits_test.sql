-- Unequal splits: shares and exact amounts are validated and stored in participant order.
\set a '''aaaaaaaa-0000-0000-0000-000000000011'''

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
$$;
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', label; end if;
end $$;
create or replace function pg_temp.fails(statement text, expected_hint text, label text) returns void language plpgsql as $$
declare
  v_hint text;
begin
  begin
    execute statement;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if expected_hint is not null and v_hint is distinct from expected_hint then
      raise exception 'FAILED: % (hint %, expected %)', label, v_hint, expected_hint;
    end if;
    return;
  end;
  raise exception 'FAILED: % (no error)', label;
end $$;

insert into auth.users (id) values (:a);

set role authenticated;
select pg_temp.act_as(:a);
select public.create_group('Split', 'EUR', 0::smallint, 'Anna', array['Ben', 'Clara']) as gid \gset
select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select id as clara from public.members where group_id = :'gid' and name = 'Clara' \gset

-- Shares keep their order -----------------------------------------------------
select gen_random_uuid() as e1 \gset
select public.save_expense(:'e1', :'gid', 'Essen', 9000, current_date, :'anna',
  array[:'clara', :'anna']::uuid[], false, 'shares', array[2, 1]::bigint[]);
select pg_temp.check((select split_kind = 'shares' and participant_ids = array[:'clara', :'anna']::uuid[] and split_values = array[2, 1]::bigint[]
  from public.expenses where id = :'e1'), 'shares stored in the order sent');

-- Editing back to equal clears the values.
select public.save_expense(:'e1', :'gid', 'Essen', 9000, current_date, :'anna', array[:'clara', :'anna', :'anna']::uuid[]);
select pg_temp.check((select split_kind = 'equal' and split_values is null and cardinality(participant_ids) = 2
  from public.expenses where id = :'e1'), 'equal split dedupes and clears values');

-- Exact amounts must add up ---------------------------------------------------
select gen_random_uuid() as e2 \gset
select public.save_expense(:'e2', :'gid', 'Skischule', 36000, current_date, :'ben',
  array[:'ben', :'clara']::uuid[], false, 'exact', array[24000, 12000]::bigint[]);
select pg_temp.check((select split_values = array[24000, 12000]::bigint[] from public.expenses where id = :'e2'), 'exact stored');

select pg_temp.fails(format(
  'select public.save_expense(gen_random_uuid(), %L, %L, 36000, current_date, %L, array[%L, %L]::uuid[], false, %L, array[20000, 12000]::bigint[])',
  :'gid', 'Falsch', :'ben', :'ben', :'clara', 'exact'), 'invalid_split', 'exact amounts must add up');
select pg_temp.fails(format(
  'select public.save_expense(gen_random_uuid(), %L, %L, 1000, current_date, %L, array[%L, %L]::uuid[], false, %L, array[1]::bigint[])',
  :'gid', 'Falsch', :'ben', :'ben', :'clara', 'shares'), 'invalid_split', 'one value per participant');
select pg_temp.fails(format(
  'select public.save_expense(gen_random_uuid(), %L, %L, 1000, current_date, %L, array[%L, %L]::uuid[], false, %L, array[1, 0]::bigint[])',
  :'gid', 'Falsch', :'ben', :'ben', :'clara', 'shares'), 'invalid_split', 'no zero weights');
select pg_temp.fails(format(
  'select public.save_expense(gen_random_uuid(), %L, %L, 1000, current_date, %L, array[%L, %L]::uuid[], false, %L, array[1, 1]::bigint[])',
  :'gid', 'Falsch', :'ben', :'ben', :'ben', 'shares'), 'invalid_split', 'no duplicate participants with values');
select pg_temp.fails(format(
  'select public.save_expense(gen_random_uuid(), %L, %L, 1000, current_date, %L, array[%L]::uuid[], false, %L, array[1]::bigint[])',
  :'gid', 'Falsch', :'ben', :'ben', 'thirds'), 'invalid_split', 'unknown split kind');
select pg_temp.fails(format(
  'select public.save_expense(gen_random_uuid(), %L, %L, 1000, current_date, %L, array[%L]::uuid[], true, %L, array[1000]::bigint[])',
  :'gid', 'Ausgleich', :'ben', :'clara', 'exact'), 'invalid_settlement', 'settlements are always equal');

reset role;
