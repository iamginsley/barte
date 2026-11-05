-- Payment details: normalized on save, visible only to people who share a group.
\set a '''aaaaaaaa-0000-0000-0000-000000000021'''
\set b '''bbbbbbbb-0000-0000-0000-000000000022'''
\set c '''cccccccc-0000-0000-0000-000000000023'''

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
$$;
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', label; end if;
end $$;
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

set role authenticated;

-- Saving normalizes ------------------------------------------------------------
select pg_temp.act_as(:a);
select public.set_payment_details(' https://www.PayPal.me/AnnaHuber/12EUR ', 'de89 3704 0044 0532 0130 00', '  Anna   Huber ');
select pg_temp.check((select paypal = 'AnnaHuber' and iban = 'DE89370400440532013000' and account_holder = 'Anna Huber'
  from public.payment_details where user_id = :a), 'link, spaces and case normalized');

select pg_temp.fails($$select public.set_payment_details('anna huber!', null, null)$$, 'invalid_paypal', 'bad PayPal name');
select pg_temp.fails($$select public.set_payment_details(null, 'DE89370400440532013001', null)$$, 'invalid_iban', 'IBAN checksum');
select pg_temp.fails($$select public.set_payment_details(null, 'XX12', null)$$, 'invalid_iban', 'IBAN too short');
select pg_temp.fails($$insert into public.payment_details (user_id, paypal) values (auth.uid(), 'direct')$$, null, 'no direct writes');

-- Only people in a shared group see them -----------------------------------------
select public.create_group('WG', 'EUR', 0::smallint, 'Anna', array['Ben']) as gid \gset
select invite_code as code from public.groups where id = :'gid' \gset
select id as ben from public.members where group_id = :'gid' and name = 'Ben' \gset

select pg_temp.act_as(:b);
select pg_temp.check((select count(*) = 0 from public.payment_details), 'B sees nothing before joining');
select public.join_group(:'code', :'ben');
select pg_temp.check((select paypal = 'AnnaHuber' from public.payment_details where user_id = :a), 'B sees A after joining');

select pg_temp.act_as(:c);
select pg_temp.check((select count(*) = 0 from public.payment_details), 'outsider C sees nothing');

-- Clearing removes the row -------------------------------------------------------
select pg_temp.act_as(:a);
select public.set_payment_details('', ' ', 'Anna');
select pg_temp.check((select count(*) = 0 from public.payment_details where user_id = :a), 'empty details delete the row');

-- PayPal only: no account holder without an IBAN.
select public.set_payment_details('annah', null, 'Anna');
select pg_temp.check((select account_holder is null from public.payment_details where user_id = :a), 'holder only with IBAN');

-- Devices: only your own rows ----------------------------------------------------
select public.register_device(repeat('ab', 32), 'sandbox');
select pg_temp.check((select count(*) = 1 from public.device_tokens), 'A sees the own device');
select pg_temp.act_as(:b);
select pg_temp.check((select count(*) = 0 from public.device_tokens), 'B does not see A''s device');
-- The same phone signed in as B moves the token over.
select public.register_device(repeat('AB', 32), 'production');
select pg_temp.check((select user_id = :b and environment = 'production' from public.device_tokens), 'token moves to the new account');
select public.unregister_device(repeat('ab', 32));
select pg_temp.check((select count(*) = 0 from public.device_tokens), 'unregister removes it');

-- Deleting the account removes payment details and devices -------------------------
select pg_temp.act_as(:a);
select public.register_device(repeat('cd', 32), 'sandbox');
select public.delete_my_account();
reset role;
select pg_temp.check((select count(*) = 0 from public.payment_details where user_id = :a), 'payment details deleted with the account');
select pg_temp.check((select count(*) = 0 from public.device_tokens where user_id = :a), 'devices deleted with the account');
