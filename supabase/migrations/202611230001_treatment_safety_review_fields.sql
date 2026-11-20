-- ТЕПЛИЦА PRO / 202611230001_treatment_safety_review_fields.sql
-- Add fields used by the treatment-safety review UI. Existing rows remain unverified.
alter table public.treatment_safety
  add column if not exists source_url text,
  add column if not exists source_checked_at timestamptz,
  add column if not exists harvest_wait_minutes integer,
  add column if not exists reentry_wait_minutes integer,
  add column if not exists label_review_attested boolean not null default false,
  add column if not exists scope_review_attested boolean not null default false,
  add column if not exists intervals_review_attested boolean not null default false;

alter table public.treatment_safety
  drop constraint if exists treatment_safety_harvest_wait_minutes_check,
  drop constraint if exists treatment_safety_reentry_wait_minutes_check;

alter table public.treatment_safety
  add constraint treatment_safety_harvest_wait_minutes_check
    check (harvest_wait_minutes is null or harvest_wait_minutes >= 0),
  add constraint treatment_safety_reentry_wait_minutes_check
    check (reentry_wait_minutes is null or reentry_wait_minutes >= 0);

comment on column public.treatment_safety.source_url is
  'HTTPS reference to the official current register or product label, entered by the responsible specialist.';
comment on column public.treatment_safety.source_checked_at is
  'Date/time when the responsible specialist checked the cited source.';
