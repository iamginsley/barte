-- Pushes are written on the server, so it needs to know each phone's language. The app sends the
-- language it shows (de or en) plus the phone's region as a BCP 47 tag, e.g. "en-GB", which also
-- picks the money format. Older app versions don't send it; they are German.

alter table public.device_tokens
  add column language text not null default 'de'
    check (char_length(language) <= 35 and language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$');

-- The new parameter has a default, so builds that don't send it keep working.
drop function public.register_device(json, text, text);

-- A phone can change hands (sign out, other person signs in), so registering moves the token
-- to the caller instead of failing on someone else's row. A malformed language falls back to German
-- rather than losing the token.
create function public.register_device(hasura_session json, p_token text, p_environment text, p_language text default null)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  -- "en_GB" and "EN-GB" both become "en-GB": lower-case language, the rest as sent.
  v_language text := replace(btrim(coalesce(p_language, '')), '_', '-');
begin
  if char_length(v_language) > 35 or v_language !~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$' then
    v_language := 'de';
  else
    v_language := lower(split_part(v_language, '-', 1)) || substr(v_language, char_length(split_part(v_language, '-', 1)) + 1);
  end if;
  insert into public.device_tokens (token, user_id, environment, language)
  values (lower(p_token), public.session_user_id(hasura_session), p_environment, v_language)
  on conflict (token) do update
    set user_id = excluded.user_id, environment = excluded.environment, language = excluded.language, updated_at = now();
end;
$$;
