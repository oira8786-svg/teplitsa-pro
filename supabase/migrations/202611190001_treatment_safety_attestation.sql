-- ТЕПЛИЦА PRO / 202611190001_treatment_safety_attestation.sql
-- Require explicit human attestations before a treatment can be marked verified.
-- This migration does not determine registration status, application rates,
-- harvest intervals or re-entry intervals from external sources.

alter table public.treatment_safety
  add column if not exists label_review_attested boolean not null default false,
  add column if not exists scope_review_attested boolean not null default false,
  add column if not exists intervals_review_attested boolean not null default false;

-- Older "verified" rows did not capture all three attestations. Keep their
-- recorded dates as historical evidence, but require a fresh review before
-- the row can again be treated as verified.
update public.treatment_safety
set verification_status = 'needs_review',
    verified_by = null,
    verified_at = null
where verification_status = 'verified'
  and (
    label_review_attested is not true
    or scope_review_attested is not true
    or intervals_review_attested is not true
  );

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'treatment_safety_verified_requires_attestations'
      and conrelid = 'public.treatment_safety'::regclass
  ) then
    alter table public.treatment_safety
      add constraint treatment_safety_verified_requires_attestations
      check (
        verification_status <> 'verified'
        or (
          label_review_attested
          and scope_review_attested
          and intervals_review_attested
          and registration_reference is not null
          and crop_and_site_scope is not null
          and label_version is not null
          and source_url is not null
          and source_checked_at is not null
          and harvest_wait_minutes is not null
          and harvest_wait_minutes >= 0
          and reentry_wait_minutes is not null
          and reentry_wait_minutes >= 0
          and verified_by is not null
          and verified_at is not null
        )
      ) not valid;
  end if;
end;
$$;

alter table public.treatment_safety
  validate constraint treatment_safety_verified_requires_attestations;

-- Remove the earlier RPC signature so clients cannot bypass the attestations
-- by calling the older overload.
drop function if exists public.verify_treatment_safety(
  uuid,uuid,text,text,text,text,timestamptz,integer,integer,text
);

create or replace function public.verify_treatment_safety(
  p_organization_id uuid,
  p_operation_id uuid,
  p_registration_reference text,
  p_crop_and_site_scope text,
  p_label_version text,
  p_source_url text,
  p_source_checked_at timestamptz,
  p_harvest_wait_minutes integer,
  p_reentry_wait_minutes integer,
  p_label_review_attested boolean,
  p_scope_review_attested boolean,
  p_intervals_review_attested boolean,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_safety_id uuid;
  v_performed_at timestamptz;
  v_operation_type text;
  v_registration_country char(2);
  v_registration_status text;
  v_registration_number text;
  v_registration_valid_until date;
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

  if p_registration_reference is null
    or length(trim(p_registration_reference)) = 0
    or p_crop_and_site_scope is null
    or length(trim(p_crop_and_site_scope)) = 0
    or length(trim(p_crop_and_site_scope)) > 1000
    or p_label_version is null
    or length(trim(p_label_version)) = 0
    or length(trim(p_label_version)) > 120 then
    raise exception 'Registration reference, crop/site scope and label version are required'
      using errcode = '22023';
  end if;

  if p_source_url is null
    or lower(trim(p_source_url)) not like 'https://%'
    or length(trim(p_source_url)) > 2048 then
    raise exception 'An HTTPS source URL is required for safety verification'
      using errcode = '22023';
  end if;

  if p_source_checked_at is null or p_source_checked_at > now() then
    raise exception 'Source check time must be present and cannot be in the future'
      using errcode = '22023';
  end if;

  if p_harvest_wait_minutes is null or p_harvest_wait_minutes < 0
    or p_reentry_wait_minutes is null or p_reentry_wait_minutes < 0 then
    raise exception 'Both safety intervals must be explicitly confirmed in minutes'
      using errcode = '22023';
  end if;

  if p_label_review_attested is not true
    or p_scope_review_attested is not true
    or p_intervals_review_attested is not true then
    raise exception 'All label, crop/site and interval review attestations are required'
      using errcode = '22023';
  end if;

  select
    ts.id,
    ao.performed_at,
    ao.operation_type,
    ap.registration_country,
    ap.registration_status,
    ap.registration_number,
    ap.registration_valid_until
  into
    v_safety_id,
    v_performed_at,
    v_operation_type,
    v_registration_country,
    v_registration_status,
    v_registration_number,
    v_registration_valid_until
  from public.treatment_safety ts
  join public.agronomy_operations ao
    on ao.organization_id = ts.organization_id
   and ao.id = ts.operation_id
  join public.agricultural_products ap
    on ap.organization_id = ao.organization_id
   and ap.id = ao.product_id
  where ts.organization_id = p_organization_id
    and ts.operation_id = p_operation_id
  for update of ts;

  if not found then
    raise exception 'Treatment safety record not found in this organization'
      using errcode = '23503';
  end if;

  if v_operation_type not in ('chemical_treatment','biological_treatment') then
    raise exception 'Safety verification is available only for plant-protection treatments'
      using errcode = '22023';
  end if;

  if v_registration_country is distinct from 'RU'
    or v_registration_status is distinct from 'active'
    or v_registration_number is null
    or trim(v_registration_number) <> trim(p_registration_reference)
    or v_registration_valid_until is null
    or v_registration_valid_until < (now() at time zone 'Europe/Moscow')::date then
    raise exception 'Product registration is missing, mismatched or expired for the Russian jurisdiction'
      using errcode = '23514';
  end if;

  update public.treatment_safety
  set jurisdiction = 'RU',
      registration_reference = trim(p_registration_reference),
      crop_and_site_scope = trim(p_crop_and_site_scope),
      label_version = trim(p_label_version),
      source_url = trim(p_source_url),
      source_checked_at = p_source_checked_at,
      harvest_wait_minutes = p_harvest_wait_minutes,
      reentry_wait_minutes = p_reentry_wait_minutes,
      label_review_attested = true,
      scope_review_attested = true,
      intervals_review_attested = true,
      harvest_wait_until = v_performed_at + make_interval(mins => p_harvest_wait_minutes),
      reentry_allowed_from = v_performed_at + make_interval(mins => p_reentry_wait_minutes),
      verified_by = auth.uid(),
      verified_at = now(),
      verification_status = 'verified',
      notes = nullif(trim(p_notes), '')
  where id = v_safety_id
    and organization_id = p_organization_id;

  insert into public.audit_events(
    organization_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_organization_id, auth.uid(), 'treatment_safety.verified',
    'treatment_safety', v_safety_id,
    jsonb_build_object(
      'operation_id', p_operation_id,
      'registration_reference', trim(p_registration_reference),
      'label_version', trim(p_label_version),
      'source_url', trim(p_source_url),
      'source_checked_at', p_source_checked_at,
      'harvest_wait_minutes', p_harvest_wait_minutes,
      'reentry_wait_minutes', p_reentry_wait_minutes,
      'label_review_attested', true,
      'scope_review_attested', true,
      'intervals_review_attested', true
    )
  );
end;
$$;

revoke all on function public.verify_treatment_safety(
  uuid,uuid,text,text,text,text,timestamptz,integer,integer,boolean,boolean,boolean,text
) from public, anon;

grant execute on function public.verify_treatment_safety(
  uuid,uuid,text,text,text,text,timestamptz,integer,integer,boolean,boolean,boolean,text
) to authenticated;

comment on function public.verify_treatment_safety(
  uuid,uuid,text,text,text,text,timestamptz,integer,integer,boolean,boolean,boolean,text
) is 'Records a human-verified Russian registration, label, crop/site scope and explicit safety intervals with attestations and audit. It does not calculate or recommend application rates.';
