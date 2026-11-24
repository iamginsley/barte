-- Closing and reopening a group; expenses reopen it by themselves.
\set a '''aaaaaaaa-0000-0000-0000-000000000051'''
\set b '''bbbbbbbb-0000-0000-0000-000000000052'''

insert into auth.users (id) values (:a), (:b);

select id as gid from public.create_group(pg_temp.s(:a), 'Urlaub', 'EUR', 0::smallint, 'Anna', array['Ben']) \gset
select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select pg_temp.check((select closed_at is null from public.groups where id = :'gid'), 'new groups are open');

-- Only members can close
select pg_temp.fails(format('select public.set_group_closed(pg_temp.s(%L), %L, true)', :b, :'gid'), 'not_member', 'outsider cannot close');

select public.set_group_closed(pg_temp.s(:a), :'gid', true);
select closed_at as first_close from public.groups where id = :'gid' \gset
select pg_temp.check(:'first_close' <> '', 'closed');

-- Closing again keeps the original date
select public.set_group_closed(pg_temp.s(:a), :'gid', true);
select pg_temp.check((select closed_at = :'first_close'::timestamptz from public.groups where id = :'gid'), 'closing twice keeps the date');

select public.set_group_closed(pg_temp.s(:a), :'gid', false);
select pg_temp.check((select closed_at is null from public.groups where id = :'gid'), 'reopened');

-- A new expense reopens a closed group
select public.set_group_closed(pg_temp.s(:a), :'gid', true);
select id as eid from public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Fähre', 4000, '2026-11-08', :'anna', array[:'anna']::uuid[]) \gset
select pg_temp.check((select closed_at is null from public.groups where id = :'gid'), 'new expense reopens');

-- So does deleting one
select public.set_group_closed(pg_temp.s(:a), :'gid', true);
select public.delete_expense(pg_temp.s(:a), :'eid');
select pg_temp.check((select closed_at is null from public.groups where id = :'gid'), 'deleted expense reopens');

-- Other groups stay as they are
select id as other from public.create_group(pg_temp.s(:a), 'WG', 'EUR', 0::smallint, 'Anna') \gset
select public.set_group_closed(pg_temp.s(:a), :'other', true);
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Taxi', 1000, '2026-11-08', :'anna', array[:'anna']::uuid[]);
select pg_temp.check((select closed_at is not null from public.groups where id = :'other'), 'other groups stay closed');
