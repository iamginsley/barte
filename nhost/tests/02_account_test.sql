-- Deleting an account keeps shared groups for the others; groups only this person used go too.
\set a '''aaaaaaaa-0000-0000-0000-000000000011'''
\set b '''bbbbbbbb-0000-0000-0000-000000000012'''

insert into auth.users (id) values (:a), (:b);

select id as shared from public.create_group(pg_temp.s(:a), 'WG', 'EUR', 0::smallint, 'Anna', array['Ben']) \gset
select id as mine from public.create_group(pg_temp.s(:a), 'Nur ich', 'EUR', 0::smallint, 'Anna') \gset
select id as anna from public.members where group_id = :'shared' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'shared' and name = 'Ben' \gset
select invite_code as code from public.groups where id = :'shared' \gset
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'shared', 'Strom', 8000, '2026-11-01', :'anna', array[:'anna', :'ben']::uuid[]);
select public.join_group(pg_temp.s(:b), :'code', :'ben');
select public.set_payment_details(pg_temp.s(:a), 'annah', null, null);
select public.register_device(pg_temp.s(:a), repeat('cd', 32), 'sandbox');

-- A deletes their account
select public.delete_my_account(pg_temp.s(:a));
select pg_temp.check((select count(*) = 0 from auth.users where id = :a), 'auth user deleted');
select pg_temp.check((select count(*) = 0 from public.groups where id = :'mine'), 'solo group deleted');
select pg_temp.check((select count(*) = 1 from public.groups where id = :'shared'), 'shared group kept');
select pg_temp.check((select user_id is null and name = 'Anna' from public.members where id = :'anna'), 'Anna stays as a name');
select pg_temp.check((select created_by is null from public.groups where id = :'shared'), 'creator cleared');
select pg_temp.check((select created_by is null from public.expenses where group_id = :'shared'), 'expense author cleared');
select pg_temp.check((select count(*) = 1 from public.expenses where group_id = :'shared'), 'B keeps the history');
select pg_temp.check((select count(*) = 0 from public.payment_details where user_id = :a), 'payment details deleted with the account');
select pg_temp.check((select count(*) = 0 from public.device_tokens where user_id = :a), 'devices deleted with the account');

-- B is the only one left with the app: leaving takes the group along, open amounts or not
select public.leave_group(pg_temp.s(:b), :'shared');
select pg_temp.check((select count(*) = 0 from public.groups where id = :'shared'), 'the orphaned group is gone with B');

select pg_temp.fails($$select public.delete_my_account('{}')$$, 'not_signed_in', 'needs a user');
