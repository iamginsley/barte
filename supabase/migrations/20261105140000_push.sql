-- Push notifications: one row per device. The notify-group Edge Function reads these with the
-- service role; clients only ever see and change their own rows.

create table public.device_tokens (
  token text primary key check (token ~ '^[0-9a-f]{64,200}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_id_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

create policy "Own device tokens" on public.device_tokens
  for select to authenticated using (user_id = (select auth.uid()));

-- A phone can change hands (sign out, other person signs in), so registering moves the token
-- to the caller instead of failing on someone else's row.
create function public.register_device(p_token text, p_environment text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.device_tokens (token, user_id, environment)
  values (lower(p_token), auth.uid(), p_environment)
  on conflict (token) do update
    set user_id = excluded.user_id, environment = excluded.environment, updated_at = now();
$$;

create function public.unregister_device(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens where token = lower(p_token) and user_id = auth.uid();
$$;

revoke execute on function public.register_device(text, text) from public, anon;
revoke execute on function public.unregister_device(text) from public, anon;
grant execute on function public.register_device(text, text) to authenticated;
grant execute on function public.unregister_device(text) to authenticated;
