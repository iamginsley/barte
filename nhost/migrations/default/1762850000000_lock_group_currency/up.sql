-- Amounts are stored as cents without a currency of their own, so changing a group's currency
-- would only relabel them (€100 becomes £100 for everyone). Once a group has any expense or
-- settlement its currency is fixed, for every member including the creator. Name and color stay
-- editable for everyone.
create or replace function public.update_group(hasura_session json, p_group_id uuid, p_name text, p_currency text, p_color smallint)
returns setof public.api_results
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_currency text := upper(btrim(p_currency));
begin
  perform public.require_group_member(p_group_id, public.session_user_id(hasura_session));
  if exists (select 1 from public.groups g where g.id = p_group_id and g.currency is distinct from v_currency)
     and exists (select 1 from public.expenses e where e.group_id = p_group_id) then
    perform public.fail('currency_locked');
  end if;
  update public.groups
  set name = btrim(p_name), currency = v_currency, color = p_color
  where id = p_group_id;
end;
$$;
