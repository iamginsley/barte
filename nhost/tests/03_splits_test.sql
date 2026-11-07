-- Unequal splits: shares and exact amounts are validated and stored in participant order.
\set a '''aaaaaaaa-0000-0000-0000-000000000031'''

insert into auth.users (id) values (:a);

select id as gid from public.create_group(pg_temp.s(:a), 'Split', 'EUR', 0::smallint, 'Anna', array['Ben', 'Clara']) \gset
select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select id as clara from public.members where group_id = :'gid' and name = 'Clara' \gset

-- Shares keep their order -----------------------------------------------------
select gen_random_uuid() as e1 \gset
select public.save_expense(pg_temp.s(:a), :'e1', :'gid', 'Essen', 9000, current_date, :'anna',
  array[:'clara', :'anna']::uuid[], false, 'shares', array[2, 1]::bigint[]);
select pg_temp.check((select split_kind = 'shares' and participant_ids = array[:'clara', :'anna']::uuid[] and split_values = array[2, 1]::bigint[]
  from public.expenses where id = :'e1'), 'shares stored in the order sent');

-- Editing back to equal clears the values.
select public.save_expense(pg_temp.s(:a), :'e1', :'gid', 'Essen', 9000, current_date, :'anna', array[:'clara', :'anna', :'anna']::uuid[]);
select pg_temp.check((select split_kind = 'equal' and split_values is null and cardinality(participant_ids) = 2
  from public.expenses where id = :'e1'), 'equal split dedupes and clears values');

-- Exact amounts must add up ---------------------------------------------------
select gen_random_uuid() as e2 \gset
select public.save_expense(pg_temp.s(:a), :'e2', :'gid', 'Skischule', 36000, current_date, :'ben',
  array[:'ben', :'clara']::uuid[], false, 'exact', array[24000, 12000]::bigint[]);
select pg_temp.check((select split_values = array[24000, 12000]::bigint[] from public.expenses where id = :'e2'), 'exact stored');

\set call 'select public.save_expense(pg_temp.s(%L), gen_random_uuid(), %L, %L, %s, current_date, %L, %L::uuid[], %L, %L, %L::bigint[])'
select pg_temp.fails(format(:'call', :a, :'gid', 'Falsch', 36000, :'ben', array[:'ben', :'clara'], false, 'exact', '{20000,12000}'), 'invalid_split', 'exact amounts must add up');
select pg_temp.fails(format(:'call', :a, :'gid', 'Falsch', 1000, :'ben', array[:'ben', :'clara'], false, 'shares', '{1}'), 'invalid_split', 'one value per participant');
select pg_temp.fails(format(:'call', :a, :'gid', 'Falsch', 1000, :'ben', array[:'ben', :'clara'], false, 'shares', '{1,0}'), 'invalid_split', 'no zero weights');
select pg_temp.fails(format(:'call', :a, :'gid', 'Falsch', 1000, :'ben', array[:'ben', :'ben'], false, 'shares', '{1,1}'), 'invalid_split', 'no duplicate participants with values');
select pg_temp.fails(format(:'call', :a, :'gid', 'Falsch', 1000, :'ben', array[:'ben'], false, 'thirds', '{1}'), 'invalid_split', 'unknown split kind');
select pg_temp.fails(format(:'call', :a, :'gid', 'Ausgleich', 1000, :'ben', array[:'clara'], true, 'exact', '{1000}'), 'invalid_settlement', 'settlements are always equal');
