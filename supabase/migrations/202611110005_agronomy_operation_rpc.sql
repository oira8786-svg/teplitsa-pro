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
