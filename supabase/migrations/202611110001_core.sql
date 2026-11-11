-- ТЕПЛИЦА PRO / 001_core.sql
-- Fresh baseline for Supabase PostgreSQL. Review and test on a non-production project first.
create extension if not exists pgcrypto;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 160),
  country_code char(2) not null default 'RU' check (country_code = 'RU'),
  region text not null default 'Москва',
  currency char(3) not null default 'RUB' check (currency = 'RUB'),
  timezone text not null default 'Europe/Moscow',
  created_at timestamptz not null default now(),
  unique (id)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','manager','agronomist','warehouse','accountant','worker')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, user_id)
);
create index memberships_user_idx on public.memberships(user_id, active);

-- SECURITY DEFINER helpers: fixed search_path; callers cannot change membership via these functions.
create or replace function public.is_org_member(p_org uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.memberships m
    where m.organization_id = p_org and m.user_id = auth.uid() and m.active
  );
$$;

create or replace function public.has_org_role(p_org uuid, p_roles text[])
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.memberships m
    where m.organization_id = p_org and m.user_id = auth.uid()
      and m.active and m.role = any(p_roles)
  );
$$;

revoke all on function public.is_org_member(uuid) from public;
revoke all on function public.has_org_role(uuid,text[]) from public;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_role(uuid,text[]) to authenticated;

-- Safe organization bootstrap: user becomes owner only for the organization created by this RPC.
create or replace function public.create_organization(p_name text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_name is null or length(trim(p_name)) not between 1 and 160 then
    raise exception 'Invalid organization name';
  end if;
  insert into public.organizations(name) values (trim(p_name)) returning id into v_org;
  insert into public.memberships(organization_id,user_id,role)
  values (v_org, auth.uid(), 'owner');
  return v_org;
end;
$$;
revoke all on function public.create_organization(text) from public;
grant execute on function public.create_organization(text) to authenticated;

create table public.greenhouses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  area numeric(14,2) check (area is null or area > 0),
  area_unit text not null default 'm2',
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id,id)
);

create table public.greenhouse_zones (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  greenhouse_id uuid not null,
  name text not null,
  area numeric(14,2) check (area is null or area > 0),
  area_unit text not null default 'm2',
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,greenhouse_id)
    references public.greenhouses(organization_id,id)
);

create table public.crops (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  category text not null check (category in ('vegetable','flower','seedling','greens','berry','other')),
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id,id)
);

create table public.crop_varieties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  crop_id uuid not null,
  name text not null,
  supplier text,
  notes text,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,crop_id) references public.crops(organization_id,id)
);

create table public.batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  greenhouse_id uuid not null,
  zone_id uuid,
  crop_id uuid not null,
  variety_id uuid,
  batch_number text not null,
  sowing_date date,
  planting_date date,
  planned_harvest_date date,
  quantity_planted numeric(18,4) check (quantity_planted is null or quantity_planted >= 0),
  quantity_unit text not null default 'pcs',
  status text not null default 'planned'
    check (status in ('planned','growing','harvesting','finished','cancelled')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,batch_number),
  foreign key (organization_id,greenhouse_id) references public.greenhouses(organization_id,id),
  foreign key (organization_id,zone_id) references public.greenhouse_zones(organization_id,id),
  foreign key (organization_id,crop_id) references public.crops(organization_id,id),
  foreign key (organization_id,variety_id) references public.crop_varieties(organization_id,id)
);
create index batches_org_status_idx on public.batches(organization_id,status);
create index batches_org_harvest_idx on public.batches(organization_id,planned_harvest_date);

create table public.agricultural_products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  category text not null check (category in (
    'chemical_fertilizer','biological_fertilizer','chemical_pesticide',
    'biological_protection','other'
  )),
  manufacturer text,
  active_ingredient text,
  registration_country char(2),
  registration_number text,
  registration_valid_until date,
  label_document_path text,
  safety_instructions text,
  created_at timestamptz not null default now(),
  unique (organization_id,id)
);

create table public.agronomy_operations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  batch_id uuid not null,
  operation_type text not null check (operation_type in (
    'watering','fertilizing','feeding','chemical_treatment',
    'biological_treatment','inspection','transplanting','pricking_out','other'
  )),
  product_id uuid,
  performed_at timestamptz not null,
  quantity numeric(18,4) check (quantity is null or quantity >= 0),
  quantity_unit text,
  water_volume numeric(18,4) check (water_volume is null or water_volume >= 0),
  water_volume_unit text,
  worker_id uuid references auth.users(id),
  result text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,batch_id) references public.batches(organization_id,id),
  foreign key (organization_id,product_id) references public.agricultural_products(organization_id,id)
);
create index agronomy_ops_batch_time_idx on public.agronomy_operations(organization_id,batch_id,performed_at desc);

-- A verified application rule snapshot; values must come from the current official label/regulation.
create table public.treatment_safety (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  operation_id uuid not null,
  jurisdiction text not null default 'RU-MOW',
  registration_reference text,
  crop_and_site_scope text,
  label_version text,
  harvest_wait_until timestamptz,
  reentry_allowed_from timestamptz,
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  verification_status text not null default 'needs_review'
    check (verification_status in ('needs_review','verified','rejected','expired')),
  notes text,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,operation_id),
  foreign key (organization_id,operation_id)
    references public.agronomy_operations(organization_id,id)
);

-- Initial tenant isolation policies. Fine-grained write permissions are tightened in later migrations.
do $$
declare t text;
begin
  foreach t in array array[
    'organizations','memberships','greenhouses','greenhouse_zones','crops',
    'crop_varieties','batches','agricultural_products','agronomy_operations','treatment_safety'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

create policy org_select_member on public.organizations
for select to authenticated using (public.is_org_member(id));

create policy memberships_select_member on public.memberships
for select to authenticated using (public.is_org_member(organization_id));

create policy memberships_manage_owner on public.memberships
for all to authenticated
using (public.has_org_role(organization_id,array['owner']))
with check (public.has_org_role(organization_id,array['owner']));

-- Read access for active members; writes limited by role. Organization creation uses RPC above.
create policy greenhouses_read on public.greenhouses for select to authenticated
using (public.is_org_member(organization_id));
create policy greenhouses_write on public.greenhouses for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager']))
with check (public.has_org_role(organization_id,array['owner','manager']));

create policy zones_read on public.greenhouse_zones for select to authenticated
using (public.is_org_member(organization_id));
create policy zones_write on public.greenhouse_zones for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager']))
with check (public.has_org_role(organization_id,array['owner','manager']));

create policy crops_read on public.crops for select to authenticated
using (public.is_org_member(organization_id));
create policy crops_write on public.crops for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','agronomist']))
with check (public.has_org_role(organization_id,array['owner','manager','agronomist']));

create policy varieties_read on public.crop_varieties for select to authenticated
using (public.is_org_member(organization_id));
create policy varieties_write on public.crop_varieties for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','agronomist']))
with check (public.has_org_role(organization_id,array['owner','manager','agronomist']));

create policy batches_read on public.batches for select to authenticated
using (public.is_org_member(organization_id));
create policy batches_write on public.batches for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','agronomist']))
with check (public.has_org_role(organization_id,array['owner','manager','agronomist']));

create policy products_read on public.agricultural_products for select to authenticated
using (public.is_org_member(organization_id));
create policy products_write on public.agricultural_products for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','agronomist']))
with check (public.has_org_role(organization_id,array['owner','manager','agronomist']));

create policy operations_read on public.agronomy_operations for select to authenticated
using (public.is_org_member(organization_id));
create policy operations_write on public.agronomy_operations for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','agronomist','worker']))
with check (public.has_org_role(organization_id,array['owner','manager','agronomist','worker']));

create policy safety_read on public.treatment_safety for select to authenticated
using (public.is_org_member(organization_id));
create policy safety_manage on public.treatment_safety for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','agronomist']))
with check (public.has_org_role(organization_id,array['owner','manager','agronomist']));

-- No anonymous access. Grant only what the authenticated API role needs; RLS remains authoritative.
grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.organizations, public.memberships, public.greenhouses, public.greenhouse_zones,
  public.crops, public.crop_varieties, public.batches, public.agricultural_products,
  public.agronomy_operations, public.treatment_safety
to authenticated;
