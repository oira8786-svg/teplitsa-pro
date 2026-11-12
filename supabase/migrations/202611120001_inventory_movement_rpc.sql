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
