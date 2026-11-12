-- ФаёзАгро / 007_harvest_sales_payment_rpc.sql
-- Audited harvest, sale posting and payment posting. Apply after migrations 001-006.

create or replace function public.record_harvest_lot(
  p_organization_id uuid,
  p_batch_id uuid,
  p_lot_number text,
  p_harvested_at timestamptz,
  p_quantity numeric,
  p_unit text,
  p_grade text default null,
  p_quality_notes text default null,
  p_storage_location text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_lot_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.has_org_role(p_organization_id, array['owner','manager','agronomist']::text[]) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;
  if p_lot_number is null or length(trim(p_lot_number)) not between 1 and 80 then
    raise exception 'Harvest lot number is required' using errcode = '22023';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Harvest quantity must be positive' using errcode = '22023';
  end if;
  if p_harvested_at is null or p_harvested_at > now() + interval '10 minutes' then
    raise exception 'Harvest time cannot be in the future' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.measurement_units u
    where u.code = p_unit and u.dimension in ('count','mass')
  ) then
    raise exception 'Harvest unit must be a count or mass unit' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.batches b
    where b.id = p_batch_id and b.organization_id = p_organization_id
      and b.status in ('planned','growing','harvesting')
  ) then
    raise exception 'Active batch not found in this organization' using errcode = '23503';
  end if;

  insert into public.harvest_lots (
    organization_id,batch_id,lot_number,harvested_at,quantity,unit,grade,
    quality_notes,storage_location,status
  ) values (
    p_organization_id,p_batch_id,trim(p_lot_number),p_harvested_at,p_quantity,p_unit,
    nullif(trim(p_grade),''),nullif(trim(p_quality_notes),''),nullif(trim(p_storage_location),''),'available'
  ) returning id into v_lot_id;

  update public.batches set status = 'harvesting', updated_at = now()
  where id = p_batch_id and organization_id = p_organization_id and status in ('planned','growing');

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values (p_organization_id,auth.uid(),'harvest_lot.created','harvest_lot',v_lot_id,
    jsonb_build_object('batch_id',p_batch_id,'quantity',p_quantity,'unit',p_unit));

  return v_lot_id;
end;
$$;

revoke all on function public.record_harvest_lot(uuid,uuid,text,timestamptz,numeric,text,text,text,text)
from public,anon;
grant execute on function public.record_harvest_lot(uuid,uuid,text,timestamptz,numeric,text,text,text,text)
to authenticated;

create or replace function public.post_sale(
  p_organization_id uuid,
  p_sale_number text,
  p_lines jsonb,
  p_customer_id uuid default null,
  p_sold_at timestamptz default now(),
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_sale_id uuid;
  v_line record;
  v_lot public.harvest_lots%rowtype;
  v_already_sold numeric(18,4);
  v_total numeric(18,2) := 0;
  v_line_total numeric(18,2);
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.has_org_role(p_organization_id, array['owner','manager','accountant']::text[]) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;
  if p_sale_number is null or length(trim(p_sale_number)) not between 1 and 80 then
    raise exception 'Sale number is required' using errcode = '22023';
  end if;
  if p_sold_at is null or p_sold_at > now() + interval '10 minutes' then
    raise exception 'Sale time cannot be in the future' using errcode = '22023';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Sale lines must be an array' using errcode = '22023';
  end if;
  select count(*) into v_count from jsonb_array_elements(p_lines);
  if v_count < 1 or v_count > 50 then
    raise exception 'Sale must contain between 1 and 50 lines' using errcode = '22023';
  end if;
  if exists (
    select 1 from (
      select value->>'harvest_lot_id' as lot_id
      from jsonb_array_elements(p_lines)
      group by value->>'harvest_lot_id'
      having count(*) > 1
    ) duplicates
  ) then
    raise exception 'Each harvest lot may appear only once per sale' using errcode = '22023';
  end if;
  if p_customer_id is not null and not exists (
    select 1 from public.customers c
    where c.id = p_customer_id and c.organization_id = p_organization_id
  ) then
    raise exception 'Customer not found in this organization' using errcode = '23503';
  end if;

  -- Lock all affected lots in a stable order to prevent concurrent overselling.
  perform h.id
  from public.harvest_lots h
  join (
    select distinct (value->>'harvest_lot_id')::uuid as id
    from jsonb_array_elements(p_lines)
  ) requested on requested.id = h.id
  where h.organization_id = p_organization_id
  order by h.id
  for update of h;

  insert into public.sales(
    organization_id,customer_id,sale_number,sold_at,currency,status,notes,created_by
  ) values (
    p_organization_id,p_customer_id,trim(p_sale_number),p_sold_at,'RUB','confirmed',
    nullif(trim(p_notes),''),auth.uid()
  ) returning id into v_sale_id;

  for v_line in
    select * from jsonb_to_recordset(p_lines) as x(
      harvest_lot_id uuid, quantity numeric, unit text, unit_price numeric, discount numeric
    ) order by harvest_lot_id
  loop
    if v_line.harvest_lot_id is null or v_line.quantity is null or v_line.quantity <= 0
      or v_line.unit is null or v_line.unit_price is null or v_line.unit_price < 0
      or coalesce(v_line.discount,0) < 0 then
      raise exception 'Invalid sale line values' using errcode = '22023';
    end if;

    select * into v_lot
    from public.harvest_lots h
    where h.id = v_line.harvest_lot_id and h.organization_id = p_organization_id
    for update;
    if not found then
      raise exception 'Harvest lot not found in this organization' using errcode = '23503';
    end if;
    if v_lot.status not in ('available','partly_sold') then
      raise exception 'Harvest lot is not available for sale' using errcode = '23514';
    end if;
    if v_line.unit <> v_lot.unit then
      raise exception 'Sale unit must match harvest lot unit (%)',v_lot.unit using errcode = '22023';
    end if;
    v_line_total := round(v_line.quantity * v_line.unit_price,2) - coalesce(v_line.discount,0);
    if v_line_total < 0 then
      raise exception 'Discount cannot exceed line amount' using errcode = '22023';
    end if;

    select coalesce(sum(sl.quantity),0) into v_already_sold
    from public.sale_lines sl
    join public.sales s on s.id = sl.sale_id and s.organization_id = sl.organization_id
    where sl.organization_id = p_organization_id
      and sl.harvest_lot_id = v_lot.id and s.status <> 'cancelled';

    if v_line.quantity > v_lot.quantity - v_already_sold then
      raise exception 'Insufficient harvest lot balance. Available: % %',
        v_lot.quantity - v_already_sold, v_lot.unit using errcode = '23514';
    end if;

    insert into public.sale_lines(
      organization_id,sale_id,harvest_lot_id,quantity,unit,unit_price,discount
    ) values (
      p_organization_id,v_sale_id,v_lot.id,v_line.quantity,v_line.unit,v_line.unit_price,coalesce(v_line.discount,0)
    );
    v_total := v_total + v_line_total;
  end loop;

  update public.harvest_lots h
  set status = case
    when coalesce((
      select sum(sl.quantity) from public.sale_lines sl
      join public.sales s on s.id = sl.sale_id and s.organization_id = sl.organization_id
      where sl.organization_id = p_organization_id and sl.harvest_lot_id = h.id
        and s.status <> 'cancelled'
    ),0) >= h.quantity then 'sold'
    else 'partly_sold'
  end
  where h.organization_id = p_organization_id
    and h.id in (select (value->>'harvest_lot_id')::uuid from jsonb_array_elements(p_lines));

  update public.sales
  set status = case when v_total = 0 then 'paid' else 'confirmed' end
  where id = v_sale_id and organization_id = p_organization_id;

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values (p_organization_id,auth.uid(),'sale.posted','sale',v_sale_id,
    jsonb_build_object('sale_number',p_sale_number,'total_rub',v_total,'line_count',v_count));

  return v_sale_id;
end;
$$;

revoke all on function public.post_sale(uuid,text,jsonb,uuid,timestamptz,text) from public,anon;
grant execute on function public.post_sale(uuid,text,jsonb,uuid,timestamptz,text) to authenticated;

create or replace function public.record_sale_payment(
  p_organization_id uuid,
  p_sale_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_paid_at timestamptz default now(),
  p_reference_number text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_payment_id uuid;
  v_sale public.sales%rowtype;
  v_sale_total numeric(18,2);
  v_paid numeric(18,2);
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.has_org_role(p_organization_id, array['owner','manager','accountant']::text[]) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be positive' using errcode = '22023';
  end if;
  if p_payment_method not in ('cash','bank_transfer','card','other') then
    raise exception 'Unsupported payment method' using errcode = '22023';
  end if;
  if p_paid_at is null or p_paid_at > now() + interval '10 minutes' then
    raise exception 'Payment time cannot be in the future' using errcode = '22023';
  end if;

  select * into v_sale
  from public.sales s
  where s.id = p_sale_id and s.organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'Sale not found in this organization' using errcode = '23503';
  end if;
  if v_sale.status = 'cancelled' then
    raise exception 'Cancelled sale cannot receive payments' using errcode = '23514';
  end if;

  select coalesce(sum(round(sl.quantity * sl.unit_price,2) - sl.discount),0)
  into v_sale_total
  from public.sale_lines sl
  where sl.organization_id = p_organization_id and sl.sale_id = p_sale_id;

  select coalesce(sum(p.amount),0) into v_paid
  from public.payments p
  where p.organization_id = p_organization_id and p.sale_id = p_sale_id;

  if p_amount > v_sale_total - v_paid then
    raise exception 'Payment exceeds outstanding balance: % RUB', v_sale_total - v_paid
      using errcode = '23514';
  end if;

  insert into public.payments(
    organization_id,sale_id,paid_at,amount,currency,payment_method,reference_number,notes
  ) values (
    p_organization_id,p_sale_id,p_paid_at,p_amount,'RUB',p_payment_method,
    nullif(trim(p_reference_number),''),nullif(trim(p_notes),'')
  ) returning id into v_payment_id;

  v_paid := v_paid + p_amount;
  update public.sales
  set status = case when v_paid >= v_sale_total then 'paid' else 'partly_paid' end
  where id = p_sale_id and organization_id = p_organization_id;

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values (p_organization_id,auth.uid(),'sale_payment.recorded','payment',v_payment_id,
    jsonb_build_object('sale_id',p_sale_id,'amount_rub',p_amount,'payment_method',p_payment_method));

  return v_payment_id;
end;
$$;

revoke all on function public.record_sale_payment(uuid,uuid,numeric,text,timestamptz,text,text)
from public,anon;
grant execute on function public.record_sale_payment(uuid,uuid,numeric,text,timestamptz,text,text)
to authenticated;

comment on function public.record_harvest_lot(uuid,uuid,text,timestamptz,numeric,text,text,text,text)
is 'Records a tenant-scoped harvest lot and writes an audit event.';
comment on function public.post_sale(uuid,text,jsonb,uuid,timestamptz,text)
is 'Posts a sale atomically, locks harvest lots against overselling and writes an audit event.';
comment on function public.record_sale_payment(uuid,uuid,numeric,text,timestamptz,text,text)
is 'Records a payment against an outstanding sale balance and updates sale status atomically.';
