-- Groups, joining, members and expenses, as seen by three people:
-- A creates "Ski" with the names Ben and Clara. B joins as Ben. C is an outsider until joining.
-- Who may read what is decided by the Hasura permissions (scripts/test-nhost-api.sh checks those).
\set a '''aaaaaaaa-0000-0000-0000-000000000001'''
\set b '''bbbbbbbb-0000-0000-0000-000000000002'''
\set c '''cccccccc-0000-0000-0000-000000000003'''

insert into auth.users (id) values (:a), (:b), (:c);

-- A creates a group --------------------------------------------------------
select id as gid from public.create_group(pg_temp.s(:a), 'Ski', 'eur', 1::smallint, ' Anna ', array['Ben', 'Clara', '  ']) \gset

select pg_temp.check((select count(*) = 3 from public.members where group_id = :'gid'), 'three members, blank names skipped');
select pg_temp.check((select user_id = :a and name = 'Anna' from public.members where group_id = :'gid' order by created_at limit 1), 'A is the first, linked member');
select pg_temp.check((select currency = 'EUR' and created_by = :a from public.groups where id = :'gid'), 'currency upper-cased, creator set');
select pg_temp.check((select char_length(invite_code) = 8 from public.groups where id = :'gid'), 'invite code generated');

select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select id as clara from public.members where group_id = :'gid' and name = 'Clara' \gset
select invite_code as code from public.groups where id = :'gid' \gset

-- No session, no access ------------------------------------------------------
select pg_temp.fails(format('select public.create_group(%L, %L, %L, 0::smallint, %L)', '{}', 'X', 'EUR', 'X'), 'not_signed_in', 'needs a user');
select pg_temp.fails(format('select public.preview_invite(%L, %L)', '{"x-hasura-user-id": "nope"}', :'code'), 'not_signed_in', 'garbage user id');

-- Outsiders cannot write -----------------------------------------------------
select pg_temp.fails(format('select public.add_member(pg_temp.s(%L), %L, %L)', :b, :'gid', 'Eve'), 'not_member', 'outsider cannot add members');
select pg_temp.fails(
  format('select public.save_expense(pg_temp.s(%L), gen_random_uuid(), %L, %L, 100, current_date, %L, array[%L]::uuid[])', :b, :'gid', 'Hack', :'ben', :'ben'),
  'not_member', 'outsider cannot add expenses');
select pg_temp.fails(format('select public.update_group(pg_temp.s(%L), %L, %L, %L, 0::smallint)', :b, :'gid', 'X', 'EUR'), 'not_member', 'outsider cannot rename');
select pg_temp.fails(format('select public.rename_member(pg_temp.s(%L), %L, %L)', :b, :'ben', 'X'), 'not_member', 'outsider cannot rename members');
select pg_temp.fails(format('select public.regenerate_invite_code(pg_temp.s(%L), %L)', :b, :'gid'), 'not_member', 'outsider cannot reset the code');
select pg_temp.fails(format('select public.claim_member(pg_temp.s(%L), %L)', :b, :'ben'), 'not_member', 'outsider cannot claim without the code');
select pg_temp.fails(format('insert into public.api_results (id) values (%L)', :'gid'), null, 'api_results never stores rows');

-- Joining --------------------------------------------------------------------
select pg_temp.fails(format('select public.preview_invite(pg_temp.s(%L), %L)', :b, 'NOPE1234'), 'invalid_code', 'unknown code');
select pg_temp.check((select (preview ->> 'name') = 'Ski' and not (preview ->> 'is_member')::boolean
  from public.preview_invite(pg_temp.s(:b), lower(:'code'))), 'preview by code, case-insensitive');
select pg_temp.check((select jsonb_array_length(preview -> 'members') = 3 from public.preview_invite(pg_temp.s(:b), :'code')), 'preview lists members');
select pg_temp.check((select (preview -> 'members' -> 0 ->> 'is_claimed')::boolean from public.preview_invite(pg_temp.s(:b), :'code')), 'Anna shows as claimed');
select pg_temp.fails(format('select public.join_group(pg_temp.s(%L), %L, %L)', :b, :'code', :'anna'), 'member_taken', 'cannot take a claimed name');

select pg_temp.check((select id = :'gid' from public.join_group(pg_temp.s(:b), :'code', :'ben')), 'B joins as Ben');
select pg_temp.check((select (preview ->> 'is_member')::boolean from public.preview_invite(pg_temp.s(:b), :'code')), 'preview knows B is in');
select pg_temp.check((select id = :'gid' from public.join_group(pg_temp.s(:b), :'code', :'clara')), 'joining again is a no-op');
select pg_temp.check((select user_id is null from public.members where id = :'clara'), 'second join did not claim Clara');

-- Claiming a different name --------------------------------------------------
select public.claim_member(pg_temp.s(:b), :'clara');
select pg_temp.check((select user_id = :b from public.members where id = :'clara'), 'B is now Clara');
select pg_temp.check((select user_id is null from public.members where id = :'ben'), 'Ben is free again');
select pg_temp.fails(format('select public.claim_member(pg_temp.s(%L), %L)', :b, :'anna'), 'member_taken', 'cannot claim A');
select public.claim_member(pg_temp.s(:b), :'ben');

-- Expenses -------------------------------------------------------------------
\set e1 '''eeeeeeee-0000-0000-0000-000000000001'''
select public.save_expense(pg_temp.s(:b), :e1, :'gid', 'Chalet', 90000, '2026-11-01', :'anna', array[:'anna', :'ben', :'clara', :'ben']::uuid[]);
select pg_temp.check((select cardinality(participant_ids) = 3 and created_by = :b from public.expenses where id = :e1), 'duplicate participants removed, author kept');
select public.save_expense(pg_temp.s(:b), :e1, :'gid', 'Chalet', 120000, '2026-11-01', :'anna', array[:'anna', :'ben', :'clara']::uuid[]);
select pg_temp.check((select count(*) = 1 and max(amount_cents) = 120000 from public.expenses), 'save again updates');
select pg_temp.fails(
  format('select public.save_expense(pg_temp.s(%L), gen_random_uuid(), %L, %L, 100, current_date, %L, %L::uuid[])', :b, :'gid', 'Nobody', :'anna', '{}'),
  'no_participants', 'needs participants');
select pg_temp.fails(
  format('select public.save_expense(pg_temp.s(%L), gen_random_uuid(), %L, %L, 0, current_date, %L, array[%L]::uuid[])', :b, :'gid', 'Zero', :'anna', :'anna'),
  null, 'amount must be positive');
select pg_temp.fails(
  format('select public.save_expense(pg_temp.s(%L), gen_random_uuid(), %L, %L, 100, current_date, %L, array[%L]::uuid[])', :b, :'gid', 'Stranger', :'anna', gen_random_uuid()),
  'unknown_member', 'participants must be in the group');
select pg_temp.fails(
  format('select public.save_expense(pg_temp.s(%L), gen_random_uuid(), %L, %L, 100, current_date, %L, array[%L, %L]::uuid[], true)', :b, :'gid', 'Ausgleich', :'ben', :'anna', :'clara'),
  'invalid_settlement', 'settlement has one receiver');
select public.save_expense(pg_temp.s(:b), gen_random_uuid(), :'gid', 'Ausgleich', 40000, '2026-11-02', :'ben', array[:'anna']::uuid[], true);

-- An expense id from another group cannot be overwritten.
select id as other from public.create_group(pg_temp.s(:c), 'Andere', 'EUR', 0::smallint, 'Chris') \gset
select id as chris from public.members where group_id = :'other' \gset
select pg_temp.fails(
  format('select public.save_expense(pg_temp.s(%L), %L, %L, %L, 100, current_date, %L, array[%L]::uuid[])', :c, :e1, :'other', 'Klau', :'chris', :'chris'),
  'not_member', 'cannot move an expense into another group');
select pg_temp.fails(format('select public.delete_expense(pg_temp.s(%L), %L)', :c, :e1), 'not_member', 'outsider cannot delete expenses');

-- Members --------------------------------------------------------------------
select public.rename_member(pg_temp.s(:b), :'clara', 'Clara S.');
select pg_temp.check((select name = 'Clara S.' from public.members where id = :'clara'), 'rename');
select pg_temp.fails(format('select public.remove_member(pg_temp.s(%L), %L)', :b, :'clara'), 'member_involved', 'cannot remove someone in expenses');
select pg_temp.fails(format('select public.remove_member(pg_temp.s(%L), %L)', :b, :'anna'), 'member_linked', 'cannot remove someone with the app');
select id as david from public.add_member(pg_temp.s(:b), :'gid', 'David') \gset
select public.remove_member(pg_temp.s(:b), :'david');
select pg_temp.check((select count(*) = 3 from public.members where group_id = :'gid'), 'unused name removed');
select pg_temp.fails(format('select public.add_member(pg_temp.s(%L), %L, %L)', :b, :'gid', '   '), 'empty_name', 'names cannot be blank');
select pg_temp.fails(format('select public.rename_member(pg_temp.s(%L), gen_random_uuid(), %L)', :b, 'X'), 'member_not_found', 'unknown member');

-- Deleting and leaving -------------------------------------------------------
select pg_temp.fails(format('select public.delete_group(pg_temp.s(%L), %L)', :b, :'gid'), 'not_creator', 'B cannot delete A''s group');
select public.leave_group(pg_temp.s(:b), :'gid');
select pg_temp.check((select not public.is_group_member(:'gid', :b)), 'B left');
select pg_temp.check((select user_id is null and name = 'Ben' from public.members where id = :'ben'), 'Ben stays as a name');
select pg_temp.check((select count(*) = 2 from public.expenses where group_id = :'gid'), 'expenses stay');

-- C joins as a new person
select public.join_group(pg_temp.s(:c), :'code', null, 'Chris');
select pg_temp.check((select count(*) = 4 from public.members where group_id = :'gid'), 'Chris added');

-- A regenerates the code: the old one stops working
select code as newcode from public.regenerate_invite_code(pg_temp.s(:a), :'gid') \gset
select pg_temp.check(:'newcode' <> :'code', 'new code');
select pg_temp.fails(format('select public.join_group(pg_temp.s(%L), %L, %L)', :b, :'code', :'ben'), 'invalid_code', 'old code no longer works');

-- The creator deletes for everyone
select public.delete_group(pg_temp.s(:a), :'gid');
select pg_temp.check((select count(*) = 0 from public.groups where id = :'gid'), 'group deleted');
select pg_temp.check((select count(*) = 0 from public.expenses where group_id = :'gid'), 'expenses deleted');
select pg_temp.check((select count(*) = 0 from public.members where group_id = :'gid'), 'members deleted');

-- The last person with the app leaving deletes the group
select id as solo from public.create_group(pg_temp.s(:b), 'Solo', 'EUR', 0::smallint, 'Ben') \gset
select public.leave_group(pg_temp.s(:b), :'solo');
select pg_temp.check((select count(*) = 0 from public.groups where id = :'solo'), 'empty group removed on leave');
