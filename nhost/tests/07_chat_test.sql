-- The group chat: who can write, deleting own messages, unread counts and muting.
\set a '''aaaaaaaa-0000-0000-0000-000000000071'''
\set b '''bbbbbbbb-0000-0000-0000-000000000072'''
\set c '''cccccccc-0000-0000-0000-000000000073'''

insert into auth.users (id) values (:a), (:b), (:c);

select id as gid from public.create_group(pg_temp.s(:a), 'Urlaub', 'EUR', 0::smallint, 'Anna', array['Ben']) \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset
select id as anna from public.members where group_id = :'gid' and name = 'Anna' \gset
select invite_code as code from public.groups where id = :'gid' \gset
select public.join_group(pg_temp.s(:b), :'code', :'ben');
select row(g.*)::public.groups as grow from public.groups g where id = :'gid' \gset

select pg_temp.check(public.group_unread_messages(:'grow', pg_temp.s(:b)) = 0, 'nothing unread at first');

-- Sending, trimmed, with the author's member row
\set m1 '''11111111-0000-0000-0000-000000000071'''
select public.send_message(pg_temp.s(:a), :m1, :'gid', E'  Wer hat Bargeld?\n\n ');
select pg_temp.check((select body = 'Wer hat Bargeld?' and member_id = :'anna' and author_id = :a
  from public.chat_messages where id = :m1), 'message is stored trimmed with its author');

-- Sending the same id again (a retry) doesn't duplicate it
select public.send_message(pg_temp.s(:a), :m1, :'gid', 'Wer hat Bargeld?');
select pg_temp.check((select count(*) = 1 from public.chat_messages where group_id = :'gid'), 'retries are idempotent');

select pg_temp.check(public.group_unread_messages(:'grow', pg_temp.s(:b)) = 1, 'unread for the other person');
select pg_temp.check(public.group_unread_messages(:'grow', pg_temp.s(:a)) = 0, 'own messages are never unread');

select public.mark_chat_read(pg_temp.s(:b), :'gid');
select pg_temp.check(public.group_unread_messages(:'grow', pg_temp.s(:b)) = 0, 'reading clears the count');

-- Replying also marks everything before as read
select public.send_message(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Hallo?');
select pg_temp.check(public.group_unread_messages(:'grow', pg_temp.s(:b)) = 1, 'a new message is unread again');
select public.send_message(pg_temp.s(:b), gen_random_uuid(), :'gid', 'Ich!');
select pg_temp.check(public.group_unread_messages(:'grow', pg_temp.s(:b)) = 0, 'replying counts as reading');

-- About an expense of this group, not of another one
select id as eid from public.save_expense(pg_temp.s(:a), gen_random_uuid(), :'gid', 'Pizza', 4200, '2026-11-08', :'anna', array[:'anna', :'ben']::uuid[]) \gset
select public.send_message(pg_temp.s(:b), gen_random_uuid(), :'gid', 'Warum so teuer?', :'eid');
select pg_temp.check((select count(*) = 1 from public.chat_messages where expense_id = :'eid'), 'message about an expense');
select id as other from public.create_group(pg_temp.s(:c), 'Andere', 'EUR', 0::smallint, 'Clara', array[]::text[]) \gset
select pg_temp.fails(format('select public.send_message(pg_temp.s(%L), gen_random_uuid(), %L, %L, %L)', :a, :'gid', 'x', gen_random_uuid()),
  'unknown_expense', 'expense must be in the group');

-- Deleting the expense keeps the message, without the link
select public.delete_expense(pg_temp.s(:a), :'eid');
select pg_temp.check((select count(*) = 1 from public.chat_messages where body = 'Warum so teuer?' and expense_id is null), 'message outlives the expense');

-- Validation and membership
select pg_temp.fails(format('select public.send_message(pg_temp.s(%L), gen_random_uuid(), %L, %L)', :a, :'gid', E' \n '),
  'empty_message', 'empty message');
select pg_temp.fails(format('select public.send_message(pg_temp.s(%L), gen_random_uuid(), %L, %L)', :a, :'gid', repeat('x', 2001)),
  'message_too_long', 'message too long');
select pg_temp.fails(format('select public.send_message(pg_temp.s(%L), gen_random_uuid(), %L, %L)', :c, :'gid', 'Hi'),
  'not_member', 'outsiders cannot write');
select pg_temp.fails(format('select public.mark_chat_read(pg_temp.s(%L), %L)', :c, :'gid'), 'not_member', 'outsiders cannot mark read');

-- Only the author deletes, and a placeholder stays
select pg_temp.fails(format('select public.delete_message(pg_temp.s(%L), %L)', :b, :m1), 'message_not_found', 'others cannot delete');
select public.delete_message(pg_temp.s(:a), :m1);
select pg_temp.check((select body is null and deleted_at is not null from public.chat_messages where id = :m1), 'deleted keeps a placeholder');
select pg_temp.fails(format('select public.delete_message(pg_temp.s(%L), %L)', :a, :m1), 'message_not_found', 'deleting twice');

-- Muting
select public.set_chat_muted(pg_temp.s(:b), :'gid', true);
select pg_temp.check((select muted from public.chat_states where group_id = :'gid' and user_id = :b), 'muted');
select public.set_chat_muted(pg_temp.s(:b), :'gid', false);
select pg_temp.check((select not muted from public.chat_states where group_id = :'gid' and user_id = :b), 'unmuted');

-- Leaving keeps the messages under the name; deleting the account removes them
select public.leave_group(pg_temp.s(:b), :'gid');
select pg_temp.check((select count(*) = 2 from public.chat_messages where author_id = :b and member_id = :'ben'), 'messages stay after leaving');
select public.delete_my_account(pg_temp.s(:b));
select pg_temp.check((select count(*) = 0 from public.chat_messages where author_id = :b), 'account deletion removes own messages');
select pg_temp.check((select count(*) = 0 from public.chat_states where user_id = :b), 'and the read state');

-- A group that goes (the last person left) takes the chat with it
select public.leave_group(pg_temp.s(:a), :'gid');
select pg_temp.check((select count(*) = 0 from public.chat_messages where group_id = :'gid'), 'chat goes with the group');
