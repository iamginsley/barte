-- The history: every change to money or names leaves a row that nobody can edit or delete.
\set a '''aaaaaaaa-0000-0000-0000-000000000061'''
\set b '''bbbbbbbb-0000-0000-0000-000000000062'''

insert into auth.users (id) values (:a), (:b);

select id as gid from public.create_group(pg_temp.s(:a), 'Urlaub', 'EUR', 0::smallint, 'Anna', array['Ben']) \gset
select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select invite_code as code from public.groups where id = :'gid' \gset
select public.join_group(pg_temp.s(:b), :'code', :'ben');
select pg_temp.check((select count(*) = 0 from public.group_events where group_id = :'gid'), 'creating and joining leave no events');

-- Adding, changing and deleting an expense
select id as eid from public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Pizza', 4200, '2026-11-08', :'anna', array[:'anna', :'ben']::uuid[]) \gset
select pg_temp.check((select kind = 'expense_added' and actor_id = :a and actor_name = 'Anna' and subject_id = :'eid'
  and old is null and (new ->> 'amount_cents')::bigint = 4200
  from public.group_events where group_id = :'gid' order by created_at desc limit 1), 'expense_added with actor and snapshot');

-- Saving the same values again leaves no trace
select public.save_expense(pg_temp.s(:a), :'eid', :'gid', 'Pizza', 4200, '2026-11-08', :'anna', array[:'anna', :'ben']::uuid[]);
select pg_temp.check((select count(*) = 1 from public.group_events where subject_id = :'eid'), 'unchanged save is not logged');

-- B lowers the amount: old and new are both kept
select public.save_expense(pg_temp.s(:b), :'eid', :'gid', 'Pizza', 2400, '2026-11-08', :'anna', array[:'anna', :'ben']::uuid[]);
select pg_temp.check((select kind = 'expense_changed' and actor_id = :b and actor_name = 'Ben'
  and (old ->> 'amount_cents')::bigint = 4200 and (new ->> 'amount_cents')::bigint = 2400
  from public.group_events where subject_id = :'eid' order by created_at desc limit 1), 'expense_changed keeps before and after');

select public.delete_expense(pg_temp.s(:b), :'eid');
select pg_temp.check((select kind = 'expense_deleted' and new is null and old ->> 'title' = 'Pizza'
  from public.group_events where subject_id = :'eid' order by created_at desc limit 1), 'expense_deleted keeps the last version');

-- Settlements
select id as sid from public.save_expense(pg_temp.s(:b), gen_random_uuid(), :'gid', 'Ausgleich', 1000, '2026-11-08', :'ben', array[:'anna']::uuid[], true) \gset
select public.delete_expense(pg_temp.s(:a), :'sid');
select pg_temp.check((select array_agg(kind order by created_at) = array['settlement_added', 'settlement_deleted']
  from public.group_events where subject_id = :'sid'), 'settlements are logged as such');

-- Group and member changes
select public.update_group(pg_temp.s(:a), :'gid', 'Urlaub 2026', 'CHF', 3::smallint);
select pg_temp.check((select kind = 'group_updated' and old ->> 'currency' = 'EUR' and new ->> 'currency' = 'CHF'
  from public.group_events where group_id = :'gid' order by created_at desc limit 1), 'name and currency changes');
select public.update_group(pg_temp.s(:a), :'gid', 'Urlaub 2026', 'CHF', 5::smallint);
select pg_temp.check((select kind <> 'group_updated' or new ->> 'currency' = 'CHF'
  from public.group_events where group_id = :'gid' order by created_at desc limit 1)
  and (select count(*) = 1 from public.group_events where group_id = :'gid' and kind = 'group_updated'), 'color alone is not logged');

select public.set_group_closed(pg_temp.s(:a), :'gid', true);
select public.set_group_closed(pg_temp.s(:b), :'gid', false);
select pg_temp.check((select array_agg(kind order by created_at) = array['group_closed', 'group_reopened']
  from public.group_events where group_id = :'gid' and kind like 'group_%ed' and kind <> 'group_updated'), 'closing and reopening');

select id as clara from public.add_member(pg_temp.s(:a), :'gid', 'Clara') \gset
select public.rename_member(pg_temp.s(:b), :'clara', 'Klara');
select public.remove_member(pg_temp.s(:a), :'clara');
select pg_temp.check((select array_agg(kind order by created_at) = array['member_added', 'member_renamed', 'member_removed']
  from public.group_events where subject_id = :'clara'), 'member added, renamed, removed');

-- Nobody can rewrite history, not even the database owner
select pg_temp.fails(format('update public.group_events set new = null where group_id = %L', :'gid'), null, 'events cannot be edited');
select pg_temp.fails(format('delete from public.group_events where group_id = %L', :'gid'), null, 'events cannot be deleted');

-- Deleting the whole group takes its history with it
select public.delete_group(pg_temp.s(:a), :'gid');
select pg_temp.check((select count(*) = 0 from public.group_events where group_id = :'gid'), 'history goes with the group');

-- Deleting an account keeps the shared history, with the name it had
select id as g2 from public.create_group(pg_temp.s(:a), 'WG', 'EUR', 0::smallint, 'Anna', array['Ben']) \gset
select id as ben2 from public.members where group_id = :'g2' and name = 'Ben' \gset
select invite_code as code2 from public.groups where id = :'g2' \gset
select public.join_group(pg_temp.s(:b), :'code2', :'ben2');
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'g2', 'Strom', 8000, '2026-11-08', :'ben2', array[:'ben2']::uuid[]);
select public.delete_my_account(pg_temp.s(:a));
select pg_temp.check((select count(*) = 1 and bool_and(actor_name = 'Anna')
  from public.group_events where group_id = :'g2'), 'history survives the account deletion');
