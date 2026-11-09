-- One name per account, the same in every group.
\set a '''aaaaaaaa-0000-0000-0000-000000000081'''
\set b '''bbbbbbbb-0000-0000-0000-000000000082'''
\set c '''cccccccc-0000-0000-0000-000000000083'''

insert into auth.users (id) values (:a), (:b), (:c);

-- Without an account name, the typed one becomes it
select pg_temp.check((select code is null from public.sync_my_name(pg_temp.s(:a))), 'no name before anything happened');
select id as g1 from public.create_group(pg_temp.s(:a), 'Ski', 'EUR', 0::smallint, 'Anna', array['Benni', 'Clara']) \gset
select pg_temp.check(public.account_name(:a) = 'Anna', 'creating a group sets the account name');

-- Later groups use the account name, whatever was typed
select id as g2 from public.create_group(pg_temp.s(:a), 'WG', 'EUR', 0::smallint, 'Annika', array['Ben']) \gset
select pg_temp.check((select name = 'Anna' from public.members where group_id = :'g2' and user_id = :a), 'account name wins over typed name');

-- B has an account name and joins as the typed-in "Benni": the expenses stay, the name follows the account
select public.set_my_name(pg_temp.s(:b), 'Benjamin');
select id as benni from public.members where group_id = :'g1' and name = 'Benni' \gset
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'g1', 'Pizza', 3000, '2026-11-08', :'benni', array[:'benni']::uuid[]);
select invite_code as code1 from public.groups where id = :'g1' \gset
select public.join_group(pg_temp.s(:b), :'code1', :'benni');
select pg_temp.check((select name = 'Benjamin' and user_id = :b from public.members where id = :'benni'), 'joining as a typed name takes the account name');
select pg_temp.check((select count(*) = 1 from public.expenses where payer_id = :'benni'), 'and keeps its expenses');

-- C has no account name yet and joins as a new person
select invite_code as code2 from public.groups where id = :'g2' \gset
select public.join_group(pg_temp.s(:c), :'code2', null, 'Chris');
select pg_temp.check(public.account_name(:c) = 'Chris', 'joining as new sets the account name');
select public.join_group(pg_temp.s(:c), :'code1', null, 'Christoph');
select pg_temp.check((select name = 'Chris' from public.members where group_id = :'g1' and user_id = :c), 'second group gets the same name');

-- Nobody renames someone who uses the app, names typed in can still be fixed
select pg_temp.fails(format('select public.rename_member(pg_temp.s(%L), %L, %L)', :a, :'benni', 'Bennyboy'), 'member_linked', 'cannot rename an app user');
select id as clara from public.members where group_id = :'g1' and name = 'Clara' \gset
select public.rename_member(pg_temp.s(:a), :'clara', 'Klara');
select pg_temp.check((select name = 'Klara' from public.members where id = :'clara'), 'typed names stay editable');

-- Changing the account name changes it everywhere, and the history shows it
select pg_temp.check((select code = 'Ben' from public.set_my_name(pg_temp.s(:b), '  Ben ')), 'set_my_name returns the clean name');
select pg_temp.check((select bool_and(name = 'Ben') and count(*) = 1 from public.members where user_id = :b), 'renamed in every group');
select pg_temp.check((select count(*) = 1 from public.group_events where subject_id = :'benni' and kind = 'member_renamed'
  and old ->> 'name' = 'Benjamin' and new ->> 'name' = 'Ben'), 'the rename is in the history');
select pg_temp.fails(format('select public.set_my_name(pg_temp.s(%L), %L)', :b, '  '), 'empty_name', 'name cannot be blank');

-- sync_my_name returns the account name and ignores the phone's guess once there is one
select pg_temp.check((select code = 'Ben' from public.sync_my_name(pg_temp.s(:b), 'Benjamin')), 'sync keeps the account name');

-- Deleting the account deletes the profile
select public.delete_my_account(pg_temp.s(:c));
select pg_temp.check((select count(*) = 0 from public.profiles where user_id = :c), 'profile goes with the account');
