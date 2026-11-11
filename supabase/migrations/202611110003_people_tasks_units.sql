-- ТЕПЛИЦА PRO / 003_people_tasks_payroll_audit.sql
create table public.employee_profiles (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid, full_name text not null, phone text, job_title text,
 employment_status text not null default 'active' check (employment_status in ('active','on_leave','inactive')),
 hired_on date, notes text, created_at timestamptz not null default now(),
 unique (organization_id,id), unique (organization_id,user_id),
 foreign key (organization_id,user_id) references public.memberships(organization_id,user_id)
);
create table public.tasks (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 title text not null, description text, greenhouse_id uuid, batch_id uuid,
 assigned_user_id uuid references auth.users(id), assigned_employee_id uuid, created_by uuid references auth.users(id),
 priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
 status text not null default 'open' check (status in ('open','in_progress','done','cancelled')),
 due_at timestamptz, completed_at timestamptz, completion_note text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique (organization_id,id),
 foreign key (organization_id,greenhouse_id) references public.greenhouses(organization_id,id),
 foreign key (organization_id,batch_id) references public.batches(organization_id,id),
 foreign key (organization_id,assigned_employee_id) references public.employee_profiles(organization_id,id)
);
create index tasks_org_status_due_idx on public.tasks(organization_id,status,due_at);
create table public.payroll_accruals (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 employee_id uuid not null, period_start date not null, period_end date not null,
 accrual_type text not null check (accrual_type in ('salary','hourly','piecework','bonus','allowance','deduction','other')),
 amount numeric(18,2) not null check (amount >= 0), currency char(3) not null default 'RUB' check (currency = 'RUB'),
 description text, approved_by uuid references auth.users(id), created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), unique (organization_id,id), check (period_end >= period_start),
 foreign key (organization_id,employee_id) references public.employee_profiles(organization_id,id)
);
create table public.payroll_payments (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 accrual_id uuid not null, paid_at timestamptz not null default now(),
 amount numeric(18,2) not null check (amount > 0), currency char(3) not null default 'RUB' check (currency = 'RUB'),
 payment_reference text, created_by uuid references auth.users(id), created_at timestamptz not null default now(),
 unique (organization_id,id), foreign key (organization_id,accrual_id) references public.payroll_accruals(organization_id,id)
);
create table public.audit_events (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 actor_user_id uuid references auth.users(id), action text not null, entity_type text not null, entity_id uuid,
 occurred_at timestamptz not null default now(), request_id text, reason text, metadata jsonb not null default '{}'::jsonb,
 unique (organization_id,id)
);
create index audit_events_org_time_idx on public.audit_events(organization_id,occurred_at desc);
create table public.notes_and_attachments (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 title text, body text, greenhouse_id uuid, batch_id uuid, storage_path text, mime_type text,
 uploaded_by uuid references auth.users(id), created_at timestamptz not null default now(), unique (organization_id,id),
 foreign key (organization_id,greenhouse_id) references public.greenhouses(organization_id,id),
 foreign key (organization_id,batch_id) references public.batches(organization_id,id)
);
create table public.measurement_units (
 code text primary key, display_name text not null,
 dimension text not null check (dimension in ('count','mass','volume','area','length','time','temperature','energy','concentration')),
 base_unit_code text, factor_to_base numeric(24,12), is_base boolean not null default false,
 check ((is_base and factor_to_base is null and base_unit_code is null) or (not is_base and factor_to_base > 0 and base_unit_code is not null))
);
insert into public.measurement_units(code,display_name,dimension,base_unit_code,factor_to_base,is_base) values
 ('pcs','штука','count',null,null,true),('mg','миллиграмм','mass',null,null,true),
 ('g','грамм','mass','mg',1000,false),('kg','килограмм','mass','mg',1000000,false),('t','тонна','mass','mg',1000000000,false),
 ('ml','миллилитр','volume',null,null,true),('l','литр','volume','ml',1000,false),('m3','кубический метр','volume','ml',1000000,false),
 ('mm','миллиметр','length',null,null,true),('cm','сантиметр','length','mm',10,false),('m','метр','length','mm',1000,false),
 ('cm2','квадратный сантиметр','area',null,null,true),('m2','квадратный метр','area','cm2',10000,false),('ha','гектар','area','cm2',100000000,false),
 ('min','минута','time',null,null,true),('h','час','time','min',60,false),('day','сутки','time','min',1440,false),
 ('C','градус Цельсия','temperature',null,null,true),('Wh','ватт-час','energy',null,null,true),('kWh','киловатт-час','energy','Wh',1000,false)
on conflict (code) do nothing;
alter table public.employee_profiles enable row level security;
alter table public.tasks enable row level security;
alter table public.payroll_accruals enable row level security;
alter table public.payroll_payments enable row level security;
alter table public.audit_events enable row level security;
alter table public.notes_and_attachments enable row level security;
alter table public.measurement_units enable row level security;
create policy employee_read on public.employee_profiles for select to authenticated using (public.is_org_member(organization_id));
create policy employee_manage on public.employee_profiles for all to authenticated
 using (public.has_org_role(organization_id,array['owner','manager']))
 with check (public.has_org_role(organization_id,array['owner','manager']));
create policy tasks_read on public.tasks for select to authenticated using (public.is_org_member(organization_id));
create policy tasks_manage on public.tasks for all to authenticated
 using (public.has_org_role(organization_id,array['owner','manager','agronomist']))
 with check (public.has_org_role(organization_id,array['owner','manager','agronomist']));
create policy tasks_worker_update on public.tasks for update to authenticated
 using (assigned_user_id = auth.uid() and public.is_org_member(organization_id))
 with check (assigned_user_id = auth.uid() and public.is_org_member(organization_id));
create policy payroll_read on public.payroll_accruals for select to authenticated
 using (public.has_org_role(organization_id,array['owner','manager','accountant']));
create policy payroll_manage on public.payroll_accruals for all to authenticated
 using (public.has_org_role(organization_id,array['owner','accountant']))
 with check (public.has_org_role(organization_id,array['owner','accountant']));
create policy payroll_payments_read on public.payroll_payments for select to authenticated
 using (public.has_org_role(organization_id,array['owner','manager','accountant']));
create policy payroll_payments_manage on public.payroll_payments for all to authenticated
 using (public.has_org_role(organization_id,array['owner','accountant']))
 with check (public.has_org_role(organization_id,array['owner','accountant']));
create policy audit_read on public.audit_events for select to authenticated
 using (public.has_org_role(organization_id,array['owner','manager']));
create policy notes_read on public.notes_and_attachments for select to authenticated using (public.is_org_member(organization_id));
create policy notes_write on public.notes_and_attachments for all to authenticated
 using (public.is_org_member(organization_id)) with check (public.is_org_member(organization_id));
create policy units_read on public.measurement_units for select to authenticated using (true);
grant select,insert,update,delete on public.employee_profiles,public.tasks,public.notes_and_attachments to authenticated;
grant select,insert,update,delete on public.payroll_accruals,public.payroll_payments to authenticated;
grant select on public.audit_events,public.measurement_units to authenticated;
