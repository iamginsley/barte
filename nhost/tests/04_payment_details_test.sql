-- Payment details are normalized on save; devices move between accounts on the same phone.
\set a '''aaaaaaaa-0000-0000-0000-000000000041'''
\set b '''bbbbbbbb-0000-0000-0000-000000000042'''

insert into auth.users (id) values (:a), (:b);

-- Saving normalizes ------------------------------------------------------------
select public.set_payment_details(pg_temp.s(:a), ' https://www.PayPal.me/AnnaHuber/12EUR ', 'de89 3704 0044 0532 0130 00', '  Anna   Huber ');
select pg_temp.check((select paypal = 'AnnaHuber' and iban = 'DE89370400440532013000' and account_holder = 'Anna Huber'
  from public.payment_details where user_id = :a), 'link, spaces and case normalized');

select pg_temp.fails(format('select public.set_payment_details(pg_temp.s(%L), %L, null, null)', :a, 'anna huber!'), 'invalid_paypal', 'bad PayPal name');
select pg_temp.fails(format('select public.set_payment_details(pg_temp.s(%L), null, %L, null)', :a, 'DE89370400440532013001'), 'invalid_iban', 'IBAN checksum');
select pg_temp.fails(format('select public.set_payment_details(pg_temp.s(%L), null, %L, null)', :a, 'XX12'), 'invalid_iban', 'IBAN too short');

-- Clearing removes the row -------------------------------------------------------
select public.set_payment_details(pg_temp.s(:a), '', ' ', 'Anna');
select pg_temp.check((select count(*) = 0 from public.payment_details where user_id = :a), 'empty details delete the row');

-- PayPal only: no account holder without an IBAN.
select public.set_payment_details(pg_temp.s(:a), 'annah', null, 'Anna');
select pg_temp.check((select account_holder is null from public.payment_details where user_id = :a), 'holder only with IBAN');

-- Devices -----------------------------------------------------------------------
select public.register_device(pg_temp.s(:a), repeat('ab', 32), 'sandbox');
select pg_temp.check((select user_id = :a from public.device_tokens), 'A registered the device');
-- The same phone signed in as B moves the token over.
select public.register_device(pg_temp.s(:b), repeat('AB', 32), 'production');
select pg_temp.check((select count(*) = 1 and bool_and(user_id = :b and environment = 'production') from public.device_tokens), 'token moves to the new account');
-- A can no longer remove B's token.
select public.unregister_device(pg_temp.s(:a), repeat('ab', 32));
select pg_temp.check((select count(*) = 1 from public.device_tokens), 'only own tokens can be removed');
select public.unregister_device(pg_temp.s(:b), repeat('ab', 32));
select pg_temp.check((select count(*) = 0 from public.device_tokens), 'unregister removes it');
select pg_temp.fails(format('select public.register_device(pg_temp.s(%L), %L, %L)', :a, 'not-a-token', 'sandbox'), null, 'tokens are hex');

-- Device language ---------------------------------------------------------------
select public.register_device(pg_temp.s(:a), repeat('ef', 32), 'sandbox');
select pg_temp.check((select language = 'de' from public.device_tokens where token = repeat('ef', 32)), 'older apps without a language are German');
select public.register_device(pg_temp.s(:a), repeat('ef', 32), 'sandbox', 'EN_GB');
select pg_temp.check((select language = 'en-GB' from public.device_tokens where token = repeat('ef', 32)), 'language stored as a BCP 47 tag');
select public.register_device(pg_temp.s(:a), repeat('ef', 32), 'sandbox', 'de-AT');
select pg_temp.check((select language = 'de-AT' from public.device_tokens where token = repeat('ef', 32)), 'switching the phone language updates it');
select public.register_device(pg_temp.s(:a), repeat('ef', 32), 'sandbox', 'en; drop table x');
select pg_temp.check((select language = 'de' from public.device_tokens where token = repeat('ef', 32)), 'malformed languages fall back to German');
select pg_temp.fails(format('update public.device_tokens set language = %L', 'not a tag'), null, 'the column only takes tags');
select public.unregister_device(pg_temp.s(:a), repeat('ef', 32));
