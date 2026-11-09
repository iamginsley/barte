-- A chat per group: short messages between the people in it, optionally about one expense.
-- The app shows them together with the group history, so "why did you change the pizza?" sits
-- right below the change itself.
--
-- Messages can't be edited. Their author can delete them, which keeps a "deleted" placeholder so
-- the conversation still makes sense. Deleting an account deletes that person's messages.
--
-- Each new message fires a Hasura event trigger (nhost/metadata) that calls the chat-message
-- function, which sends the push notifications to everyone else who hasn't muted the chat.

create table public.chat_messages (
  -- Chosen by the app, so a retry after a lost connection doesn't send the message twice.
  id uuid primary key,
  group_id uuid not null references public.groups (id) on delete cascade,
  -- The author's member row, for the name; stays when they leave the group.
  member_id uuid references public.members (id) on delete set null,
  author_id uuid not null references auth.users (id) on delete cascade,
  -- Null once deleted.
  body text,
  -- The expense the message is about, if any.
  expense_id uuid references public.expenses (id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint chat_messages_body check (
    case when deleted_at is null then char_length(body) between 1 and 2000 else body is null end
  )
);

create index chat_messages_group_idx on public.chat_messages (group_id, created_at desc);

-- How far each person has read a group's chat, and whether they muted it.
create table public.chat_states (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  read_at timestamptz not null default '-infinity',
  muted boolean not null default false,
  primary key (group_id, user_id)
);

-- Helpers -------------------------------------------------------------------

create function public.touch_chat_read(p_group_id uuid, p_user uuid)
returns void
language sql
volatile
set search_path = ''
as $$
  insert into public.chat_states (group_id, user_id, read_at) values (p_group_id, p_user, clock_timestamp())
  on conflict (group_id, user_id) do update set read_at = greatest(public.chat_states.read_at, excluded.read_at);
$$;

-- API -----------------------------------------------------------------------

create function public.send_message(hasura_session json, p_id uuid, p_group_id uuid, p_body text, p_expense_id uuid default null)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
  -- Leading and trailing blank lines and spaces go, line breaks inside stay.
  v_body text := regexp_replace(coalesce(p_body, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
begin
  perform public.require_group_member(p_group_id, v_user);
  if v_body = '' then
    perform public.fail('empty_message');
  end if;
  if char_length(v_body) > 2000 then
    perform public.fail('message_too_long');
  end if;
  if p_expense_id is not null
     and not exists (select 1 from public.expenses where id = p_expense_id and group_id = p_group_id) then
    perform public.fail('unknown_expense');
  end if;
  insert into public.chat_messages (id, group_id, member_id, author_id, body, expense_id)
  values (
    p_id, p_group_id,
    (select id from public.members where group_id = p_group_id and user_id = v_user),
    v_user, v_body, p_expense_id
  )
  on conflict (id) do nothing;
  -- Writing means having read everything before.
  perform public.touch_chat_read(p_group_id, v_user);
  return query select p_id, null::text, null::jsonb;
end;
$$;

create function public.delete_message(hasura_session json, p_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
begin
  update public.chat_messages
  set body = null, expense_id = null, deleted_at = clock_timestamp()
  where id = p_id and author_id = v_user and deleted_at is null;
  if not found then
    perform public.fail('message_not_found');
  end if;
end;
$$;

create function public.mark_chat_read(hasura_session json, p_group_id uuid)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
begin
  perform public.require_group_member(p_group_id, v_user);
  perform public.touch_chat_read(p_group_id, v_user);
end;
$$;

create function public.set_chat_muted(hasura_session json, p_group_id uuid, p_muted boolean)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_user uuid := public.session_user_id(hasura_session);
begin
  perform public.require_group_member(p_group_id, v_user);
  insert into public.chat_states (group_id, user_id, muted) values (p_group_id, v_user, p_muted)
  on conflict (group_id, user_id) do update set muted = excluded.muted;
end;
$$;

-- Messages from others the caller hasn't seen yet; a computed field on groups.
create function public.group_unread_messages(g public.groups, hasura_session json)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer
  from public.chat_messages m
  where m.group_id = g.id
    and m.deleted_at is null
    and m.author_id is distinct from nullif(hasura_session ->> 'x-hasura-user-id', '')::uuid
    and m.created_at > coalesce((
      select s.read_at from public.chat_states s
      where s.group_id = g.id and s.user_id = nullif(hasura_session ->> 'x-hasura-user-id', '')::uuid
    ), '-infinity');
$$;
