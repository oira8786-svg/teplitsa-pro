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
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if not public.has_org_role(p_organization_id,array['owner','manager','accountant']::text[]) then
    raise exception 'Insufficient organization role' using errcode = '42501';
  end if;
  if p_expense_date is null or p_expense_date > current_date + 1 then
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
