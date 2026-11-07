-- Shared by every test file (psql runs it in the same session first).

-- The session Hasura passes to the functions for a signed-in person.
create or replace function pg_temp.s(p_user uuid) returns json language sql as $$
  select json_build_object('x-hasura-role', 'user', 'x-hasura-user-id', p_user);
$$;
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', label; end if;
end $$;
-- Runs a statement and expects it to fail with the given message (or any error when null).
-- The functions put the hint for the app in the message.
create or replace function pg_temp.fails(statement text, expected text, label text) returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when others then
    if expected is not null and sqlerrm is distinct from expected then
      raise exception 'FAILED: % (got "%", expected "%")', label, sqlerrm, expected;
    end if;
    if expected is not null and sqlstate <> '22000' then
      raise exception 'FAILED: % (state %, Hasura only passes 22000 on)', label, sqlstate;
    end if;
    return;
  end;
  raise exception 'FAILED: % (no error)', label;
end $$;
