-- ТЕПЛИЦА PRO / 202611210001_agricultural_product_registration_status.sql
-- Add the registration status field used by the treatment-safety journal.
-- Existing products remain unverified; never assume they are registered.

alter table public.agricultural_products
  add column if not exists registration_status text not null default 'not_checked';

alter table public.agricultural_products
  drop constraint if exists agricultural_products_registration_status_check;

alter table public.agricultural_products
  add constraint agricultural_products_registration_status_check
  check (registration_status in ('not_checked','active','expired','suspended','revoked'));

comment on column public.agricultural_products.registration_status is
  'Manual Russian registration status. Default not_checked; active requires independent verification against the official current register.';
