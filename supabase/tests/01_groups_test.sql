-- Groups, joining, members and expenses, as seen by three people:
-- A creates "Ski" with the names Ben and Clara. B joins as Ben. C is an outsider until joining.
\set a '''aaaaaaaa-0000-0000-0000-000000000001'''
\set b '''bbbbbbbb-0000-0000-0000-000000000002'''
\set c '''cccccccc-0000-0000-0000-000000000003'''

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
$$;
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', label; end if;
end $$;
-- Runs a statement and expects it to fail with the given hint (or any error when hint is null).
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

insert into auth.users (id) values (:a), (:b), (:c);

-- A creates a group --------------------------------------------------------
set role authenticated;
select pg_temp.act_as(:a);
select public.create_group('Ski', 'eur', 1::smallint, ' Anna ', array['Ben', 'Clara', '  ']) as gid \gset

select pg_temp.check((select count(*) = 3 from public.members where group_id = :'gid'), 'three members, blank names skipped');
select pg_temp.check((select user_id = :a and name = 'Anna' from public.members where group_id = :'gid' order by created_at limit 1), 'A is the first, linked member');
select pg_temp.check((select currency = 'EUR' from public.groups where id = :'gid'), 'currency upper-cased');
select pg_temp.check((select char_length(invite_code) = 8 from public.groups where id = :'gid'), 'invite code generated');

select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select id as clara from public.members where group_id = :'gid' and name = 'Clara' \gset
select invite_code as code from public.groups where id = :'gid' \gset

-- Outsiders see nothing and cannot write ------------------------------------
select pg_temp.act_as(:b);
select pg_temp.check((select count(*) = 0 from public.groups), 'B sees no groups before joining');
select pg_temp.check((select count(*) = 0 from public.members), 'B sees no members before joining');
select pg_temp.fails(format('select public.add_member(%L, %L)', :'gid', 'Eve'), 'not_member', 'outsider cannot add members');
select pg_temp.fails(
  format('select public.save_expense(gen_random_uuid(), %L, %L, 100, current_date, %L, array[%L]::uuid[])', :'gid', 'Hack', :'ben', :'ben'),
  'not_member', 'outsider cannot add expenses');
select pg_temp.fails(format('select public.update_group(%L, %L, %L, 0::smallint)', :'gid', 'X', 'EUR'), 'not_member', 'outsider cannot rename');
select pg_temp.fails(format('insert into public.groups (name) values (%L)', 'Direct'), null, 'no direct inserts');

-- Joining --------------------------------------------------------------------
select pg_temp.fails(format('select public.preview_invite(%L)', 'NOPE1234'), 'invalid_code', 'unknown code');
select pg_temp.check((select (public.preview_invite(lower(:'code')) ->> 'name') = 'Ski'), 'preview by code, case-insensitive');
select pg_temp.check((select jsonb_array_length(public.preview_invite(:'code') -> 'members') = 3), 'preview lists members');
select pg_temp.check((select (public.preview_invite(:'code') -> 'members' -> 0 ->> 'is_claimed')::boolean), 'Anna shows as claimed');
select pg_temp.fails(format('select public.join_group(%L, %L)', :'code', :'anna'), 'member_taken', 'cannot take a claimed name');

select pg_temp.check((select public.join_group(:'code', :'ben') = :'gid'), 'B joins as Ben');
select pg_temp.check((select count(*) = 1 from public.groups), 'B now sees the group');
select pg_temp.check((select count(*) = 3 from public.members), 'B sees all members');
select pg_temp.check((select public.join_group(:'code', :'clara') = :'gid'), 'joining again is a no-op');
select pg_temp.check((select user_id is null from public.members where id = :'clara'), 'second join did not claim Clara');

-- Anonymous callers cannot use the API
reset role;
set role anon;
select pg_temp.act_as(null);
select pg_temp.fails(format('select public.preview_invite(%L)', :'code'), null, 'anon cannot preview');
select pg_temp.fails(format('select public.join_group(%L, %L)', :'code', :'clara'), null, 'anon cannot join');
reset role;
set role authenticated;

-- Claiming a different name --------------------------------------------------
select pg_temp.act_as(:b);
select public.claim_member(:'clara');
select pg_temp.check((select user_id = :b from public.members where id = :'clara'), 'B is now Clara');
select pg_temp.check((select user_id is null from public.members where id = :'ben'), 'Ben is free again');
select pg_temp.fails(format('select public.claim_member(%L)', :'anna'), 'member_taken', 'cannot claim A');
select public.claim_member(:'ben');

-- Expenses -------------------------------------------------------------------
\set e1 '''eeeeeeee-0000-0000-0000-000000000001'''
select public.save_expense(:e1, :'gid', 'Chalet', 90000, '2026-11-01', :'anna', array[:'anna', :'ben', :'clara', :'ben']::uuid[]);
select pg_temp.check((select cardinality(participant_ids) = 3 from public.expenses where id = :e1), 'duplicate participants removed');
select public.save_expense(:e1, :'gid', 'Chalet', 120000, '2026-11-01', :'anna', array[:'anna', :'ben', :'clara']::uuid[]);
select pg_temp.check((select count(*) = 1 and max(amount_cents) = 120000 from public.expenses), 'save again updates');
select pg_temp.fails(
  format('select public.save_expense(gen_random_uuid(), %L, %L, 100, current_date, %L, %L::uuid[])', :'gid', 'Nobody', :'anna', '{}'),
  'no_participants', 'needs participants');
select pg_temp.fails(
  format('select public.save_expense(gen_random_uuid(), %L, %L, 0, current_date, %L, array[%L]::uuid[])', :'gid', 'Zero', :'anna', :'anna'),
  null, 'amount must be positive');
select pg_temp.fails(
  format('select public.save_expense(gen_random_uuid(), %L, %L, 100, current_date, %L, array[%L]::uuid[])', :'gid', 'Stranger', :'anna', gen_random_uuid()),
  'unknown_member', 'participants must be in the group');
select pg_temp.fails(
  format('select public.save_expense(gen_random_uuid(), %L, %L, 100, current_date, %L, array[%L, %L]::uuid[], true)', :'gid', 'Ausgleich', :'ben', :'anna', :'clara'),
  'invalid_settlement', 'settlement has one receiver');
select public.save_expense(gen_random_uuid(), :'gid', 'Ausgleich', 40000, '2026-11-02', :'ben', array[:'anna']::uuid[], true);

-- Members --------------------------------------------------------------------
select public.rename_member(:'clara', 'Clara S.');
select pg_temp.check((select name = 'Clara S.' from public.members where id = :'clara'), 'rename');
select pg_temp.fails(format('select public.remove_member(%L)', :'clara'), 'member_involved', 'cannot remove someone in expenses');
select pg_temp.fails(format('select public.remove_member(%L)', :'anna'), 'member_linked', 'cannot remove someone with the app');
select public.add_member(:'gid', 'David') as david \gset
select public.remove_member(:'david');
select pg_temp.check((select count(*) = 3 from public.members), 'unused name removed');
select pg_temp.fails(format('select public.add_member(%L, %L)', :'gid', '   '), 'empty_name', 'names cannot be blank');

-- Deleting and leaving -------------------------------------------------------
select pg_temp.fails(format('select public.delete_group(%L)', :'gid'), 'not_creator', 'B cannot delete A''s group');
select public.leave_group(:'gid');
select pg_temp.check((select count(*) = 0 from public.groups), 'B left');
reset role;
select pg_temp.check((select user_id is null and name = 'Ben' from public.members where id = :'ben'), 'Ben stays as a name');
select pg_temp.check((select count(*) = 2 from public.expenses where group_id = :'gid'), 'expenses stay');

-- C joins as a new person and sees the history
set role authenticated;
select pg_temp.act_as(:c);
select public.join_group(:'code', null, 'Chris');
select pg_temp.check((select count(*) = 4 from public.members), 'Chris added');
select pg_temp.check((select count(*) = 2 from public.expenses), 'C sees the expenses');

-- A regenerates the code: the old one stops working
select pg_temp.act_as(:a);
select public.regenerate_invite_code(:'gid') as newcode \gset
select pg_temp.act_as(:b);
select pg_temp.fails(format('select public.join_group(%L, %L)', :'code', :'ben'), 'invalid_code', 'old code no longer works');

-- The creator deletes for everyone
select pg_temp.act_as(:a);
select public.delete_group(:'gid');
reset role;
select pg_temp.check((select count(*) = 0 from public.groups where id = :'gid'), 'group deleted');
select pg_temp.check((select count(*) = 0 from public.expenses where group_id = :'gid'), 'expenses deleted');
select pg_temp.check((select count(*) = 0 from public.members where group_id = :'gid'), 'members deleted');

-- The last person with the app leaving deletes the group
set role authenticated;
select pg_temp.act_as(:b);
select public.create_group('Solo', 'EUR', 0::smallint, 'Ben') as solo \gset
select public.leave_group(:'solo');
reset role;
select pg_temp.check((select count(*) = 0 from public.groups where id = :'solo'), 'empty group removed on leave');
