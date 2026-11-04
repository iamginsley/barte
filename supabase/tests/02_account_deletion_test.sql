-- Deleting an account keeps shared groups for the others; groups only this person used go too.
\set a '''aaaaaaaa-0000-0000-0000-000000000011'''
\set b '''bbbbbbbb-0000-0000-0000-000000000012'''

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
$$;
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', label; end if;
end $$;

reset role;
insert into auth.users (id) values (:a), (:b);

set role authenticated;
select pg_temp.act_as(:a);
select public.create_group('WG', 'EUR', 0::smallint, 'Anna', array['Ben']) as shared \gset
select public.create_group('Nur ich', 'EUR', 0::smallint, 'Anna') as mine \gset
select id as anna from public.members where group_id = :'shared' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'shared' and name = 'Ben' \gset
select invite_code as code from public.groups where id = :'shared' \gset
select public.save_expense(gen_random_uuid(), :'shared', 'Strom', 8000, '2026-11-01', :'anna', array[:'anna', :'ben']::uuid[]);

select pg_temp.act_as(:b);
select public.join_group(:'code', :'ben');

-- A deletes their account
select pg_temp.act_as(:a);
select public.delete_my_account();
reset role;
select pg_temp.check((select count(*) = 0 from auth.users where id = :a), 'auth user deleted');
select pg_temp.check((select count(*) = 0 from public.groups where id = :'mine'), 'solo group deleted');
select pg_temp.check((select count(*) = 1 from public.groups where id = :'shared'), 'shared group kept');
select pg_temp.check((select user_id is null and name = 'Anna' from public.members where id = :'anna'), 'Anna stays as a name');
select pg_temp.check((select created_by is null from public.groups where id = :'shared'), 'creator cleared');

-- B still sees everything and may now delete the group, being the only one left with the app
set role authenticated;
select pg_temp.act_as(:b);
select pg_temp.check((select count(*) = 1 from public.expenses), 'B keeps the history');
select public.delete_group(:'shared');
reset role;
select pg_temp.check((select count(*) = 0 from public.groups where id = :'shared'), 'B could delete the orphaned group');

-- Anonymous callers cannot use it
set role anon;
select pg_temp.act_as(null);
do $$ begin
  perform public.delete_my_account();
  raise exception 'FAILED: anon could call';
exception when others then
  if sqlerrm like 'FAILED%' then raise; end if;
end $$;
reset role;
