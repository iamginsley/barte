-- The currency of a group is fixed once it has an expense or settlement; name and color are not.
\set a '''aaaaaaaa-0000-0000-0000-000000000091'''
\set b '''bbbbbbbb-0000-0000-0000-000000000092'''

insert into auth.users (id) values (:a), (:b);

select id as gid from public.create_group(pg_temp.s(:a), 'Urlaub', 'EUR', 0::smallint, 'Anna', array['Ben']) \gset
select invite_code as code from public.groups where id = :'gid' \gset
select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select public.join_group(pg_temp.s(:b), :'code', :'ben');

-- Without expenses anyone can change the currency
select public.update_group(pg_temp.s(:b), :'gid', 'Urlaub', 'gbp', 0::smallint);
select pg_temp.check((select currency = 'GBP' from public.groups where id = :'gid'), 'currency changes without expenses');
select public.update_group(pg_temp.s(:a), :'gid', 'Urlaub', 'EUR', 0::smallint);

-- With an expense nobody can, not even the creator
select id as eid from public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Fähre', 4000, '2026-11-08', :'anna', array[:'anna', :'ben']::uuid[]) \gset
select pg_temp.fails(format('select public.update_group(pg_temp.s(%L), %L, %L, %L, 0::smallint)', :a, :'gid', 'Urlaub', 'GBP'), 'currency_locked', 'creator cannot change the currency');
select pg_temp.fails(format('select public.update_group(pg_temp.s(%L), %L, %L, %L, 0::smallint)', :b, :'gid', 'Urlaub', 'USD'), 'currency_locked', 'member cannot change the currency');
select pg_temp.check((select currency = 'EUR' from public.groups where id = :'gid'), 'currency unchanged');

-- Name and color stay editable for everyone; the same currency in other spelling is no change
select public.update_group(pg_temp.s(:b), :'gid', ' Sommer ', ' eur ', 3::smallint);
select pg_temp.check((select name = 'Sommer' and color = 3 and currency = 'EUR' from public.groups where id = :'gid'), 'non-creator renames and recolors');

-- Settlements count as well
select public.delete_expense(pg_temp.s(:a), :'eid');
select public.save_expense(pg_temp.s(:b), gen_random_uuid(), :'gid', 'Ausgleich', 2000, '2026-11-08', :'ben', array[:'anna']::uuid[], true);
select pg_temp.fails(format('select public.update_group(pg_temp.s(%L), %L, %L, %L, 0::smallint)', :a, :'gid', 'Sommer', 'GBP'), 'currency_locked', 'a settlement locks the currency');

-- Outsiders still get not_member first
select pg_temp.fails(format('select public.update_group(pg_temp.s(%L), %L, %L, %L, 0::smallint)', gen_random_uuid(), :'gid', 'X', 'GBP'), 'not_member', 'outsider');
