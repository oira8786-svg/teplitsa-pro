-- ТЕПЛИЦА PRO / 002_inventory_harvest_sales.sql
-- All relations are tenant-scoped through composite foreign keys.
create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  location_description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id,id)
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agricultural_product_id uuid,
  name text not null,
  sku text,
  category text not null check (category in (
    'fertilizer','plant_protection','seeds','substrate','packaging',
    'fuel','spare_parts','equipment','other'
  )),
  base_unit text not null,
  minimum_stock numeric(18,4) not null default 0 check (minimum_stock >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,agricultural_product_id)
    references public.agricultural_products(organization_id,id)
);
create unique index inventory_items_sku_uq
  on public.inventory_items(organization_id,sku) where sku is not null;

-- Append-only ledger. Direction is defined by movement_type; quantity is always positive.
create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  warehouse_id uuid not null,
  item_id uuid not null,
  movement_type text not null check (movement_type in (
    'receipt','issue','writeoff','adjustment_in','adjustment_out',
    'transfer_in','transfer_out','production_use','sale','reversal'
  )),
  quantity numeric(18,4) not null check (quantity > 0),
  unit text not null,
  unit_cost numeric(18,4) check (unit_cost is null or unit_cost >= 0),
  document_number text,
  occurred_at timestamptz not null default now(),
  related_batch_id uuid,
  reversal_of_id uuid,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,warehouse_id) references public.warehouses(organization_id,id),
  foreign key (organization_id,item_id) references public.inventory_items(organization_id,id),
  foreign key (organization_id,related_batch_id) references public.batches(organization_id,id),
  foreign key (organization_id,reversal_of_id)
    references public.inventory_movements(organization_id,id)
);
create unique index inventory_movement_single_reversal_uq
  on public.inventory_movements(organization_id,reversal_of_id)
  where reversal_of_id is not null;
create index inventory_movements_item_time_idx
  on public.inventory_movements(organization_id,item_id,occurred_at desc);

create table public.harvest_lots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  batch_id uuid not null,
  lot_number text not null,
  harvested_at timestamptz not null,
  quantity numeric(18,4) not null check (quantity > 0),
  unit text not null,
  grade text,
  quality_notes text,
  storage_location text,
  status text not null default 'available'
    check (status in ('available','reserved','partly_sold','sold','written_off')),
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,lot_number),
  foreign key (organization_id,batch_id) references public.batches(organization_id,id)
);
create index harvest_lots_batch_date_idx
  on public.harvest_lots(organization_id,batch_id,harvested_at desc);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  address text,
  tax_id text,
  notes text,
  created_at timestamptz not null default now(),
  unique (organization_id,id)
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid,
  sale_number text not null,
  sold_at timestamptz not null default now(),
  currency char(3) not null default 'RUB' check (currency = 'RUB'),
  status text not null default 'draft'
    check (status in ('draft','confirmed','partly_paid','paid','cancelled')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,sale_number),
  foreign key (organization_id,customer_id) references public.customers(organization_id,id)
);

create table public.sale_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sale_id uuid not null,
  harvest_lot_id uuid not null,
  quantity numeric(18,4) not null check (quantity > 0),
  unit text not null,
  unit_price numeric(18,2) not null check (unit_price >= 0),
  discount numeric(18,2) not null default 0 check (discount >= 0),
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,sale_id) references public.sales(organization_id,id),
  foreign key (organization_id,harvest_lot_id) references public.harvest_lots(organization_id,id)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sale_id uuid not null,
  paid_at timestamptz not null default now(),
  amount numeric(18,2) not null check (amount > 0),
  currency char(3) not null default 'RUB' check (currency = 'RUB'),
  payment_method text not null check (payment_method in ('cash','bank_transfer','card','other')),
  reference_number text,
  notes text,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,sale_id) references public.sales(organization_id,id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  expense_date date not null,
  category text not null check (category in (
    'seeds','fertilizers','plant_protection','utilities','rent','transport',
    'repairs','payroll','packaging','other'
  )),
  description text not null,
  amount numeric(18,2) not null check (amount >= 0),
  currency char(3) not null default 'RUB' check (currency = 'RUB'),
  document_number text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id,id)
);
create index sales_org_date_idx on public.sales(organization_id,sold_at desc);
create index expenses_org_date_idx on public.expenses(organization_id,expense_date desc);

-- Initial RLS: members can read; writes are role-scoped. Ledger is read-only through direct API.
do $$
declare t text;
begin
  foreach t in array array[
    'warehouses','inventory_items','inventory_movements','harvest_lots',
    'customers','sales','sale_lines','payments','expenses'
  ] loop
    execute format('alter table public.%I enable row level security',t);
  end loop;
end $$;

create policy warehouses_read on public.warehouses for select to authenticated
using (public.is_org_member(organization_id));
create policy warehouses_write on public.warehouses for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','warehouse']))
with check (public.has_org_role(organization_id,array['owner','manager','warehouse']));

create policy inventory_items_read on public.inventory_items for select to authenticated
using (public.is_org_member(organization_id));
create policy inventory_items_write on public.inventory_items for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','warehouse','agronomist']))
with check (public.has_org_role(organization_id,array['owner','manager','warehouse','agronomist']));

create policy inventory_movements_read on public.inventory_movements for select to authenticated
using (public.is_org_member(organization_id));
-- No direct insert/update/delete: add audited transactional RPCs before enabling operations.

create policy harvest_lots_read on public.harvest_lots for select to authenticated
using (public.is_org_member(organization_id));
create policy harvest_lots_write on public.harvest_lots for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','agronomist']))
with check (public.has_org_role(organization_id,array['owner','manager','agronomist']));

create policy customers_read on public.customers for select to authenticated
using (public.is_org_member(organization_id));
create policy customers_write on public.customers for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','accountant']))
with check (public.has_org_role(organization_id,array['owner','manager','accountant']));

create policy sales_read on public.sales for select to authenticated
using (public.is_org_member(organization_id));
create policy sales_write on public.sales for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','accountant']))
with check (public.has_org_role(organization_id,array['owner','manager','accountant']));

create policy sale_lines_read on public.sale_lines for select to authenticated
using (public.is_org_member(organization_id));
create policy sale_lines_write on public.sale_lines for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','accountant']))
with check (public.has_org_role(organization_id,array['owner','manager','accountant']));

create policy payments_read on public.payments for select to authenticated
using (public.is_org_member(organization_id));
create policy expenses_read on public.expenses for select to authenticated
using (public.is_org_member(organization_id));
create policy expenses_write on public.expenses for all to authenticated
using (public.has_org_role(organization_id,array['owner','manager','accountant']))
with check (public.has_org_role(organization_id,array['owner','manager','accountant']));

grant select, insert, update, delete on
  public.warehouses,public.inventory_items,public.harvest_lots,public.customers,
  public.sales,public.sale_lines,public.expenses
to authenticated;
grant select on public.inventory_movements,public.payments to authenticated;
