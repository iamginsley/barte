-- Reminders: only who is owed reminds who owes, never more than is open, once a day.
\set a '''aaaaaaaa-0000-0000-0000-000000000111'''
\set b '''bbbbbbbb-0000-0000-0000-000000000112'''
\set c '''cccccccc-0000-0000-0000-000000000113'''
\set x '''dddddddd-0000-0000-0000-000000000114'''

insert into auth.users (id) values (:a), (:b), (:c), (:x);

select id as gid from public.create_group(pg_temp.s(:a), 'Urlaub', 'EUR', 0::smallint, 'Anna', array['Ben', 'Clara']) \gset
select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select id as clara from public.members where group_id = :'gid' and name = 'Clara' \gset
select invite_code as code from public.groups where id = :'gid' \gset
select public.join_group(pg_temp.s(:b), :'code', :'ben');

-- Nothing open yet
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 100)', :a, :'gid', :'ben'), 'nothing_owed', 'nothing to remind of');

-- Anna paid 90 € for all three: Ben and Clara owe 30 € each
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Hütte', 9000, '2026-11-08', :'anna', array[:'anna', :'ben', :'clara']::uuid[]);

select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 3000)', :x, :'gid', :'ben'), 'not_member', 'outsiders cannot remind');
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 3000)', :b, :'gid', :'anna'), 'nothing_owed', 'Ben owes, so he cannot remind Anna');
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 3000)', :a, :'gid', :'anna'), 'not_member', 'not yourself');
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 3000)', :a, :'gid', :'clara'), 'no_app', 'typed-in names have no phone');
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 9000)', :a, :'gid', :'ben'), 'invalid_amount', 'not more than Ben owes');
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 0)', :a, :'gid', :'ben'), 'invalid_amount', 'not nothing');

select public.remind(pg_temp.s(:a), :'gid', :'ben', 3000);
select pg_temp.check((select count(*) = 1 from public.reminders where from_member = :'anna' and to_member = :'ben' and amount_cents = 3000), 'reminder stored');
select pg_temp.check((select count(*) = 0 from public.group_events where group_id = :'gid' and kind not in ('expense_added', 'member_joined')),
  'reminders stay out of the history');
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 3000)', :a, :'gid', :'ben'), 'reminded_recently', 'once a day');

-- A day later it works again, and old reminders are cleaned up
update public.reminders set created_at = now() - interval '8 days';
select public.remind(pg_temp.s(:a), :'gid', :'ben', 3000);
select pg_temp.check((select count(*) = 1 from public.reminders where to_member = :'ben'), 'old reminder removed, new one stored');

-- Once Ben paid back, there is nothing to remind of
select public.save_expense(pg_temp.s(:b), gen_random_uuid(), :'gid', 'Ausgleich', 3000, '2026-11-08', :'ben', array[:'anna']::uuid[], true);
update public.reminders set created_at = now() - interval '1 day';
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 3000)', :a, :'gid', :'ben'), 'nothing_owed', 'Ben is square');

-- Reminders go with the group
select public.leave_group(pg_temp.s(:b), :'gid');
select public.leave_group(pg_temp.s(:a), :'gid');
select pg_temp.fails(format('select public.remind(pg_temp.s(%L), %L, %L, 100)', :a, :'gid', :'ben'), 'not_member', 'group gone');
select pg_temp.check((select count(*) = 0 from public.reminders where group_id = :'gid'), 'reminders deleted with the group');
