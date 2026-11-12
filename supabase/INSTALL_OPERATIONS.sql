-- ФаёзАгро: единый установочный скрипт серверных операций.
-- Безопасно выполнять повторно: функции создаются через CREATE OR REPLACE.
-- Выполнять в тестовом Supabase после миграций 001-004.

-- SOURCE: supabase/migrations/202611110005_agronomy_operation_rpc.sql
-- ТЕПЛИЦА PRO / 005_agronomy_operation_rpc.sql
-- Audited, tenant-scoped creation of performed agronomy operations.
-- Apply after migrations 001-004. Client writes remain revoked; all creation goes
-- through this narrow SECURITY DEFINER function.

create or replace function public.create_agronomy_operation(
  p_organization_id uuid,
  p_batch_id uuid,
  p_operation_type text,
  p_performed_at timestamptz default now(),
  p_product_id uuid default null,
  p_quantity numeric default null,
  p_quantity_unit text default null,
  p_water_volume numeric default null,
  p_water_volume_unit text default null,
  p_worker_id uuid default null,
  p_result text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_operation_id uuid;
  v_product_category text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.has_org_role(
    p_organization_id,
    array['owner','manager','agronomist']::text[]
  ) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;

  if p_operation_type not in (
    'watering','fertilizing','feeding','chemical_treatment',
    'biological_treatment','inspection','transplanting','pricking_out','other'
  ) then
    raise exception 'Unsupported operation type' using errcode = '22023';
  end if;

  if p_performed_at is null or p_performed_at > now() + interval '10 minutes' then
    raise exception 'Performed time cannot be in the future' using errcode = '22023';
  end if;

  if p_quantity is not null then
    if p_quantity <= 0 or p_quantity_unit is null then
      raise exception 'Positive quantity and unit are required together' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.measurement_units u
      where u.code = p_quantity_unit
        and u.dimension in ('count','mass','volume','concentration')
    ) then
      raise exception 'Unknown or incompatible quantity unit' using errcode = '22023';
    end if;
  elsif p_quantity_unit is not null then
    raise exception 'Quantity unit supplied without quantity' using errcode = '22023';
  end if;

  if p_water_volume is not null then
    if p_water_volume <= 0 or p_water_volume_unit is null then
      raise exception 'Positive water volume and unit are required together' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.measurement_units u
      where u.code = p_water_volume_unit and u.dimension = 'volume'
    ) then
      raise exception 'Water volume unit must be a volume unit' using errcode = '22023';
    end if;
  elsif p_water_volume_unit is not null then
    raise exception 'Water volume unit supplied without volume' using errcode = '22023';
  end if;

  if p_worker_id is not null and not exists (
    select 1 from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = p_worker_id
      and m.active
  ) then
    raise exception 'Worker must be an active member of this organization' using errcode = '23503';
  end if;

  -- The batch and product are checked inside this tenant before inserting.
  if not exists (
    select 1 from public.batches b
    where b.id = p_batch_id and b.organization_id = p_organization_id
  ) then
    raise exception 'Batch not found in this organization' using errcode = '23503';
  end if;

  if p_product_id is not null then
    select ap.category into v_product_category
    from public.agricultural_products ap
    where ap.id = p_product_id and ap.organization_id = p_organization_id;

    if v_product_category is null then
      raise exception 'Product not found in this organization' using errcode = '23503';
    end if;
  end if;

  if p_operation_type in ('fertilizing','feeding') then
    if v_product_category is null or v_product_category not in ('chemical_fertilizer','biological_fertilizer') then
      raise exception 'Select a registered fertilizer product for feeding/fertilizing' using errcode = '22023';
    end if;
  elsif p_operation_type = 'chemical_treatment' then
    if v_product_category is distinct from 'chemical_pesticide' then
      raise exception 'Select a chemical plant-protection product' using errcode = '22023';
    end if;
  elsif p_operation_type = 'biological_treatment' then
    if v_product_category is distinct from 'biological_protection' then
      raise exception 'Select a biological plant-protection product' using errcode = '22023';
    end if;
  end if;

  insert into public.agronomy_operations (
    organization_id, batch_id, operation_type, product_id, performed_at,
    quantity, quantity_unit, water_volume, water_volume_unit,
    worker_id, result, notes, created_by
  ) values (
    p_organization_id, p_batch_id, p_operation_type, p_product_id, p_performed_at,
    p_quantity, p_quantity_unit, p_water_volume, p_water_volume_unit,
    p_worker_id, nullif(trim(p_result), ''), nullif(trim(p_notes), ''), auth.uid()
  )
  returning id into v_operation_id;

  -- Safety intervals are never guessed. Every treatment starts unverified and
  -- blocks any claim that harvest/re-entry is safe until reviewed against the
  -- current official Russian product label for this crop and protected-ground use.
  if p_operation_type in ('chemical_treatment','biological_treatment') then
    insert into public.treatment_safety (
      organization_id, operation_id, jurisdiction, verification_status, notes
    ) values (
      p_organization_id, v_operation_id, 'RU', 'needs_review',
      'Требуется проверка действующей официальной инструкции препарата для культуры и условий применения.'
    );
  end if;

  insert into public.audit_events (
    organization_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_organization_id, auth.uid(), 'agronomy_operation.created',
    'agronomy_operation', v_operation_id,
    jsonb_build_object(
      'operation_type', p_operation_type,
      'batch_id', p_batch_id,
      'product_id', p_product_id
    )
  );

  return v_operation_id;
end;
$$;

revoke all on function public.create_agronomy_operation(
  uuid,uuid,text,timestamptz,uuid,numeric,text,numeric,text,uuid,text,text
) from public, anon;
grant execute on function public.create_agronomy_operation(
  uuid,uuid,text,timestamptz,uuid,numeric,text,numeric,text,uuid,text,text
) to authenticated;

comment on function public.create_agronomy_operation(
  uuid,uuid,text,timestamptz,uuid,numeric,text,numeric,text,uuid,text,text
) is 'Creates a tenant-scoped agronomy operation with role checks and audit. Treatment safety remains needs_review until official label verification.';


-- SOURCE: supabase/migrations/202611120001_inventory_movement_rpc.sql
-- ФаёзАгро / 006_inventory_movement_rpc.sql
-- Transactional, tenant-scoped stock ledger posting. Apply after migrations 001-005.

create or replace function public.post_inventory_movement(
  p_organization_id uuid,
  p_warehouse_id uuid,
  p_item_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_unit text,
  p_unit_cost numeric default null,
  p_document_number text default null,
  p_occurred_at timestamptz default now(),
  p_related_batch_id uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_movement_id uuid;
  v_base_unit text;
  v_balance numeric(18,4);
  v_delta numeric(18,4);
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.has_org_role(
    p_organization_id,
    array['owner','manager','warehouse','agronomist']::text[]
  ) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;

  if p_movement_type not in (
    'receipt','issue','writeoff','adjustment_in','adjustment_out','production_use'
  ) then
    raise exception 'Unsupported stock movement type' using errcode = '22023';
  end if;

  if p_quantity is null or p_quantity <= 0 or p_unit is null or length(trim(p_unit)) = 0 then
    raise exception 'Positive quantity and unit are required' using errcode = '22023';
  end if;

  if p_unit_cost is not null and p_unit_cost < 0 then
    raise exception 'Unit cost cannot be negative' using errcode = '22023';
  end if;

  if p_occurred_at is null or p_occurred_at > now() + interval '10 minutes' then
    raise exception 'Movement time cannot be in the future' using errcode = '22023';
  end if;

  -- Serialize postings for this warehouse/item pair so concurrent issues
  -- cannot both spend the same remaining balance.
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || p_warehouse_id::text || ':' || p_item_id::text, 0
  ));

  select i.base_unit into v_base_unit
  from public.inventory_items i
  where i.id = p_item_id
    and i.organization_id = p_organization_id
    and i.active;

  if v_base_unit is null then
    raise exception 'Active inventory item not found in this organization' using errcode = '23503';
  end if;

  if p_unit <> v_base_unit then
    raise exception 'Movement unit must match item base unit (%)', v_base_unit using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.measurement_units u
    where u.code = v_base_unit and u.dimension in ('count','mass','volume')
  ) then
    raise exception 'Inventory item has an unsupported base unit' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.warehouses w
    where w.id = p_warehouse_id
      and w.organization_id = p_organization_id
      and w.active
  ) then
    raise exception 'Active warehouse not found in this organization' using errcode = '23503';
  end if;

  if p_related_batch_id is not null and not exists (
    select 1 from public.batches b
    where b.id = p_related_batch_id
      and b.organization_id = p_organization_id
  ) then
    raise exception 'Batch not found in this organization' using errcode = '23503';
  end if;

  select coalesce(sum(
    case
      when movement_type in ('receipt','adjustment_in','transfer_in') then quantity
      when movement_type in ('issue','writeoff','adjustment_out','transfer_out','production_use','sale') then -quantity
      when movement_type = 'reversal' then
        case when exists (
          select 1 from public.inventory_movements original
          where original.organization_id = m.organization_id
            and original.id = m.reversal_of_id
            and original.movement_type in ('receipt','adjustment_in','transfer_in')
        ) then -quantity else quantity end
      else 0
    end
  ), 0)
  into v_balance
  from public.inventory_movements m
  where m.organization_id = p_organization_id
    and m.warehouse_id = p_warehouse_id
    and m.item_id = p_item_id;

  v_delta := case
    when p_movement_type in ('receipt','adjustment_in') then p_quantity
    else -p_quantity
  end;

  if v_delta < 0 and v_balance + v_delta < 0 then
    raise exception 'Insufficient stock. Available: % %', v_balance, v_base_unit
      using errcode = '23514';
  end if;

  insert into public.inventory_movements (
    organization_id, warehouse_id, item_id, movement_type, quantity, unit,
    unit_cost, document_number, occurred_at, related_batch_id, notes, created_by
  ) values (
    p_organization_id, p_warehouse_id, p_item_id, p_movement_type, p_quantity, p_unit,
    p_unit_cost, nullif(trim(p_document_number), ''), p_occurred_at,
    p_related_batch_id, nullif(trim(p_notes), ''), auth.uid()
  )
  returning id into v_movement_id;

  insert into public.audit_events (
    organization_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_organization_id, auth.uid(), 'inventory_movement.created',
    'inventory_movement', v_movement_id,
    jsonb_build_object(
      'warehouse_id', p_warehouse_id,
      'item_id', p_item_id,
      'movement_type', p_movement_type,
      'quantity', p_quantity,
      'unit', p_unit
    )
  );

  return v_movement_id;
end;
$$;

revoke all on function public.post_inventory_movement(
  uuid,uuid,uuid,text,numeric,text,numeric,text,timestamptz,uuid,text
) from public, anon;
grant execute on function public.post_inventory_movement(
  uuid,uuid,uuid,text,numeric,text,numeric,text,timestamptz,uuid,text
) to authenticated;

comment on function public.post_inventory_movement(
  uuid,uuid,uuid,text,numeric,text,numeric,text,timestamptz,uuid,text
) is 'Posts an audited stock receipt/issue/writeoff/adjustment in a tenant-scoped transaction; prevents negative stock.';


-- SOURCE: supabase/migrations/202611120002_harvest_sales_payment_rpc.sql
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


-- SOURCE: supabase/migrations/202611120003_finance_tasks_payroll_rpc.sql
-- ФаёзАгро / 008_finance_tasks_payroll_rpc.sql
-- Audited expenses, assigned tasks and payroll posting. Apply after migrations 001-007.

create or replace function public.record_expense(
  p_organization_id uuid,
  p_expense_date date,
  p_category text,
  p_description text,
  p_amount numeric,
  p_document_number text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_id uuid;
  v_timezone text;
  v_today date;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if not public.has_org_role(p_organization_id,array['owner','manager','accountant']::text[]) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;
  select timezone into v_timezone from public.organizations where id=p_organization_id;
  v_today := (now() at time zone coalesce(v_timezone,'Europe/Moscow'))::date;
  if p_expense_date is null or p_expense_date > v_today then
    raise exception 'Expense date is invalid' using errcode = '22023';
  end if;
  if p_category not in ('seeds','fertilizers','plant_protection','utilities','rent','transport','repairs','payroll','packaging','other') then
    raise exception 'Unsupported expense category' using errcode = '22023';
  end if;
  if p_description is null or length(trim(p_description)) not between 1 and 500 then
    raise exception 'Expense description is required' using errcode = '22023';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'Expense amount cannot be negative' using errcode = '22023';
  end if;

  insert into public.expenses(organization_id,expense_date,category,description,amount,currency,document_number,notes,created_by)
  values(p_organization_id,p_expense_date,p_category,trim(p_description),p_amount,'RUB',
    nullif(trim(p_document_number),''),nullif(trim(p_notes),''),auth.uid())
  returning id into v_id;

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_organization_id,auth.uid(),'expense.created','expense',v_id,
    jsonb_build_object('category',p_category,'amount_rub',p_amount,'expense_date',p_expense_date));
  return v_id;
end;
$$;

revoke all on function public.record_expense(uuid,date,text,text,numeric,text,text) from public,anon;
grant execute on function public.record_expense(uuid,date,text,text,numeric,text,text) to authenticated;

create or replace function public.create_task(
  p_organization_id uuid,
  p_title text,
  p_description text default null,
  p_greenhouse_id uuid default null,
  p_batch_id uuid default null,
  p_assigned_user_id uuid default null,
  p_assigned_employee_id uuid default null,
  p_priority text default 'normal',
  p_due_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_id uuid;
  v_employee_user uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if not public.has_org_role(p_organization_id,array['owner','manager','agronomist']::text[]) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 then
    raise exception 'Task title is required' using errcode = '22023';
  end if;
  if p_priority not in ('low','normal','high','urgent') then
    raise exception 'Unsupported task priority' using errcode = '22023';
  end if;
  if p_greenhouse_id is not null and not exists(
    select 1 from public.greenhouses where id=p_greenhouse_id and organization_id=p_organization_id
  ) then raise exception 'Greenhouse not found in this organization' using errcode = '23503'; end if;
  if p_batch_id is not null and not exists(
    select 1 from public.batches where id=p_batch_id and organization_id=p_organization_id
  ) then raise exception 'Batch not found in this organization' using errcode = '23503'; end if;
  if p_assigned_user_id is not null and not exists(
    select 1 from public.memberships where organization_id=p_organization_id
      and user_id=p_assigned_user_id and active
  ) then raise exception 'Assigned user must be an active member of this organization' using errcode = '23503'; end if;

  if p_assigned_employee_id is not null then
    select user_id into v_employee_user from public.employee_profiles
    where id=p_assigned_employee_id and organization_id=p_organization_id and employment_status='active';
    if not found then raise exception 'Active employee not found in this organization' using errcode = '23503'; end if;
    if v_employee_user is not null and p_assigned_user_id is distinct from v_employee_user then
      raise exception 'Assigned account does not match selected employee' using errcode = '22023';
    end if;
  end if;

  insert into public.tasks(
    organization_id,title,description,greenhouse_id,batch_id,assigned_user_id,
    assigned_employee_id,created_by,priority,status,due_at
  ) values (
    p_organization_id,trim(p_title),nullif(trim(p_description),''),p_greenhouse_id,p_batch_id,
    p_assigned_user_id,p_assigned_employee_id,auth.uid(),p_priority,'open',p_due_at
  ) returning id into v_id;

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_organization_id,auth.uid(),'task.created','task',v_id,
    jsonb_build_object('priority',p_priority,'assigned_user_id',p_assigned_user_id,'assigned_employee_id',p_assigned_employee_id));
  return v_id;
end;
$$;

revoke all on function public.create_task(uuid,text,text,uuid,uuid,uuid,uuid,text,timestamptz) from public,anon;
grant execute on function public.create_task(uuid,text,text,uuid,uuid,uuid,uuid,text,timestamptz) to authenticated;

create or replace function public.update_task_status(
  p_organization_id uuid,
  p_task_id uuid,
  p_status text,
  p_completion_note text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_task public.tasks%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_status not in ('open','in_progress','done','cancelled') then
    raise exception 'Unsupported task status' using errcode = '22023';
  end if;

  select * into v_task from public.tasks
  where id=p_task_id and organization_id=p_organization_id for update;
  if not found then raise exception 'Task not found in this organization' using errcode = '23503'; end if;

  if public.has_org_role(p_organization_id,array['owner','manager','agronomist']::text[]) then
    null;
  elsif v_task.assigned_user_id = auth.uid()
    and public.is_org_member(p_organization_id)
    and p_status in ('in_progress','done') then
    null;
  else
    raise exception 'Insufficient permission to change this task' using errcode = '42501';
  end if;

  update public.tasks
  set status=p_status,
      completed_at=case when p_status='done' then coalesce(completed_at,now()) else null end,
      completion_note=case when p_completion_note is not null then nullif(trim(p_completion_note),'') else completion_note end,
      updated_at=now()
  where id=p_task_id and organization_id=p_organization_id;

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_organization_id,auth.uid(),'task.status_changed','task',p_task_id,
    jsonb_build_object('old_status',v_task.status,'new_status',p_status));
end;
$$;

revoke all on function public.update_task_status(uuid,uuid,text,text) from public,anon;
grant execute on function public.update_task_status(uuid,uuid,text,text) to authenticated;

create or replace function public.create_payroll_accrual(
  p_organization_id uuid,
  p_employee_id uuid,
  p_period_start date,
  p_period_end date,
  p_accrual_type text,
  p_amount numeric,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if not public.has_org_role(p_organization_id,array['owner','accountant']::text[]) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;
  if not exists(select 1 from public.employee_profiles where id=p_employee_id
    and organization_id=p_organization_id and employment_status <> 'inactive') then
    raise exception 'Employee not found in this organization' using errcode = '23503';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then
    raise exception 'Payroll period is invalid' using errcode = '22023';
  end if;
  if p_accrual_type not in ('salary','hourly','piecework','bonus','allowance','deduction','other') then
    raise exception 'Unsupported payroll accrual type' using errcode = '22023';
  end if;
  if p_amount is null or p_amount < 0 then raise exception 'Payroll amount cannot be negative' using errcode = '22023'; end if;

  insert into public.payroll_accruals(
    organization_id,employee_id,period_start,period_end,accrual_type,amount,currency,description,approved_by,created_by
  ) values(
    p_organization_id,p_employee_id,p_period_start,p_period_end,p_accrual_type,p_amount,'RUB',
    nullif(trim(p_description),''),auth.uid(),auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_organization_id,auth.uid(),'payroll_accrual.created','payroll_accrual',v_id,
    jsonb_build_object('employee_id',p_employee_id,'amount_rub',p_amount,'period_start',p_period_start,'period_end',p_period_end));
  return v_id;
end;
$$;

revoke all on function public.create_payroll_accrual(uuid,uuid,date,date,text,numeric,text) from public,anon;
grant execute on function public.create_payroll_accrual(uuid,uuid,date,date,text,numeric,text) to authenticated;

create or replace function public.record_payroll_payment(
  p_organization_id uuid,
  p_accrual_id uuid,
  p_amount numeric,
  p_paid_at timestamptz default now(),
  p_payment_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_payment_id uuid;
  v_accrual public.payroll_accruals%rowtype;
  v_paid numeric(18,2);
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if not public.has_org_role(p_organization_id,array['owner','accountant']::text[]) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Payment amount must be positive' using errcode = '22023'; end if;
  if p_paid_at is null or p_paid_at > now() + interval '10 minutes' then
    raise exception 'Payment time cannot be in the future' using errcode = '22023';
  end if;

  select * into v_accrual from public.payroll_accruals
  where id=p_accrual_id and organization_id=p_organization_id for update;
  if not found then raise exception 'Payroll accrual not found in this organization' using errcode = '23503'; end if;

  if v_accrual.accrual_type = 'deduction' then
    raise exception 'A deduction cannot be paid as an accrual' using errcode = '23514';
  end if;

  select coalesce(sum(amount),0) into v_paid from public.payroll_payments
  where organization_id=p_organization_id and accrual_id=p_accrual_id;
  if p_amount > v_accrual.amount - v_paid then
    raise exception 'Payment exceeds unpaid payroll balance: % RUB',v_accrual.amount-v_paid using errcode = '23514';
  end if;

  insert into public.payroll_payments(organization_id,accrual_id,paid_at,amount,currency,payment_reference,created_by)
  values(p_organization_id,p_accrual_id,p_paid_at,p_amount,'RUB',nullif(trim(p_payment_reference),''),auth.uid())
  returning id into v_payment_id;

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_organization_id,auth.uid(),'payroll_payment.recorded','payroll_payment',v_payment_id,
    jsonb_build_object('accrual_id',p_accrual_id,'amount_rub',p_amount));
  return v_payment_id;
end;
$$;

revoke all on function public.record_payroll_payment(uuid,uuid,numeric,timestamptz,text) from public,anon;
grant execute on function public.record_payroll_payment(uuid,uuid,numeric,timestamptz,text) to authenticated;

comment on function public.record_expense(uuid,date,text,text,numeric,text,text)
is 'Records a tenant-scoped expense with audit.';
comment on function public.create_task(uuid,text,text,uuid,uuid,uuid,uuid,text,timestamptz)
is 'Creates a task and validates assignee membership and employee linkage.';
comment on function public.update_task_status(uuid,uuid,text,text)
is 'Updates task status with role/assignee restrictions and audit.';
comment on function public.create_payroll_accrual(uuid,uuid,date,date,text,numeric,text)
is 'Creates a payroll accrual with role checks and audit.';
comment on function public.record_payroll_payment(uuid,uuid,numeric,timestamptz,text)
is 'Records a payroll payment without allowing overpayment.';
