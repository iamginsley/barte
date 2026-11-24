-- Fair play: nobody leaves with open amounts, closing needs everyone settled, joining is logged.
\set a '''aaaaaaaa-0000-0000-0000-000000000101'''
\set b '''bbbbbbbb-0000-0000-0000-000000000102'''
\set c '''cccccccc-0000-0000-0000-000000000103'''

insert into auth.users (id) values (:a), (:b), (:c);

select id as gid from public.create_group(pg_temp.s(:a), 'Urlaub', 'EUR', 0::smallint, 'Anna', array['Ben', 'Clara']) \gset
select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select id as clara from public.members where group_id = :'gid' and name = 'Clara' \gset
select invite_code as code from public.groups where id = :'gid' \gset

-- Joining is logged: taking over a typed-in name says which one ------------------------
select public.set_my_name(pg_temp.s(:b), 'Benjamin');
select public.join_group(pg_temp.s(:b), :'code', :'ben');
select pg_temp.check((select count(*) = 1 from public.group_events where subject_id = :'ben' and kind = 'member_joined'
  and old ->> 'name' = 'Ben' and new ->> 'name' = 'Benjamin' and actor_id = :b and actor_name = 'Benjamin'), 'claim logged with both names');
select pg_temp.check((select count(*) = 0 from public.group_events where subject_id = :'ben' and kind = 'member_renamed'), 'one entry, not a rename');
select public.join_group(pg_temp.s(:c), :'code', null, 'Chris');
select pg_temp.check((select count(*) = 1 from public.group_events where group_id = :'gid' and kind = 'member_joined'
  and old is null and new ->> 'name' = 'Chris'), 'joining as someone new is logged');
select id as chris from public.members where group_id = :'gid' and user_id = :c \gset

-- Balances: 100 € for three, 33.33 / 33.33 / 33.34 in the app ----------------------------
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Hütte', 10000, '2026-11-08', :'anna', array[:'anna', :'ben', :'clara']::uuid[]);
select pg_temp.check(not public.is_settled(:'gid'), 'open amounts');
select pg_temp.check(public.is_settled(:'gid', :'chris'), 'Chris is not involved');

-- Nobody leaves with open amounts while others with Barte are still in
select pg_temp.fails(format('select public.leave_group(pg_temp.s(%L), %L)', :b, :'gid'), 'open_balance', 'Ben owes and cannot leave');
select pg_temp.fails(format('select public.leave_group(pg_temp.s(%L), %L)', :a, :'gid'), 'open_balance', 'Anna is owed and cannot leave either');
select pg_temp.fails(format('select public.set_group_closed(pg_temp.s(%L), %L, true)', :a, :'gid'), 'open_balances', 'no closing while not settled');

-- Ben pays back 33.33 €: settled for Ben (the cent of rounding is the app's business)
select public.save_expense(pg_temp.s(:b), gen_random_uuid(), :'gid', 'Ausgleich', 3333, '2026-11-08', :'ben', array[:'anna']::uuid[], true);
select pg_temp.check(public.is_settled(:'gid', :'ben'), 'Ben is settled after paying back');
select public.leave_group(pg_temp.s(:b), :'gid');
select pg_temp.check((select user_id is null from public.members where id = :'ben'), 'Ben left');
select pg_temp.check((select count(*) = 1 from public.group_events where subject_id = :'ben' and kind = 'member_left'
  and old ->> 'name' = 'Benjamin'), 'leaving is logged');

-- Clara (a typed-in name) still owes: closing stays blocked; once she paid, it works
select pg_temp.fails(format('select public.set_group_closed(pg_temp.s(%L), %L, true)', :c, :'gid'), 'open_balances', 'Clara still owes');
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Ausgleich', 3334, '2026-11-08', :'clara', array[:'anna']::uuid[], true);
select pg_temp.check(public.is_settled(:'gid'), 'everyone settled');
select public.set_group_closed(pg_temp.s(:c), :'gid', true);
select pg_temp.check((select closed_at is not null from public.groups where id = :'gid'), 'closed once settled');

-- Shares and fixed amounts count too
select id as g2 from public.create_group(pg_temp.s(:a), 'WG', 'EUR', 0::smallint, 'Anna', array['Ben']) \gset
select id as anna2 from public.members where group_id = :'g2' and name = 'Anna' \gset
select id as ben2 from public.members where group_id = :'g2' and name = 'Ben' \gset
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'g2', 'Essen', 9000, '2026-11-08', :'anna2', array[:'anna2', :'ben2']::uuid[], false, 'shares', array[1, 2]::bigint[]);
select pg_temp.check((select balance = 6000 from public.member_balances(:'g2') where member_id = :'anna2'), 'shares: Anna gets 60 €');
select public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'g2', 'Miete', 1000, '2026-11-08', :'ben2', array[:'anna2', :'ben2']::uuid[], false, 'exact', array[600, 400]::bigint[]);
select pg_temp.check((select balance = 5400 and rounded_shares = 1 from public.member_balances(:'g2') where member_id = :'anna2'),
  'fixed amounts are exact, only the shares expense is rounded');
