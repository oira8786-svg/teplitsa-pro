-- ТЕПЛИЦА PRO / 004_security_hardening.sql
-- Fail-closed hardening: sensitive business records remain readable to authorized
-- members, but direct client writes are disabled until audited transactional RPCs exist.
-- Apply after 001, 002 and 003.

-- Agronomy: workers must not write arbitrary operations directly. A future RPC will
-- validate task assignment, actor role and safety-related fields.
drop policy if exists operations_write on public.agronomy_operations;
revoke insert, update, delete on public.agronomy_operations from authenticated;

-- Inventory ledger is append-only and must only be changed by trusted RPCs.
revoke insert, update, delete on public.inventory_movements from authenticated;

-- Harvest lots, sales, sale lines, payments and expenses must be changed atomically
-- with stock/reservation/balance checks. Lock direct writes until those RPCs are added.
drop policy if exists harvest_lots_write on public.harvest_lots;
drop policy if exists sales_write on public.sales;
drop policy if exists sale_lines_write on public.sale_lines;
drop policy if exists expenses_write on public.expenses;
revoke insert, update, delete on
  public.harvest_lots, public.sales, public.sale_lines,
  public.payments, public.expenses
from authenticated;

-- Tasks: remove broad manager/worker row updates. Task transitions will be exposed
-- through a narrow RPC after assignment and allowed-field checks are implemented.
drop policy if exists tasks_manage on public.tasks;
drop policy if exists tasks_worker_update on public.tasks;
revoke insert, update, delete on public.tasks from authenticated;

-- Payroll is sensitive and must not be directly editable through the table API.
drop policy if exists payroll_manage on public.payroll_accruals;
drop policy if exists payroll_payments_manage on public.payroll_payments;
revoke insert, update, delete on
  public.payroll_accruals, public.payroll_payments
from authenticated;

-- Audit records are read-only to clients. Trusted database triggers/functions
-- will create events so users cannot forge or erase the audit trail.
revoke insert, update, delete on public.audit_events from authenticated;

-- Notes: members may add notes/attachments, but cannot rewrite or erase history.
drop policy if exists notes_write on public.notes_and_attachments;
create policy notes_insert_member on public.notes_and_attachments
for insert to authenticated
with check (public.is_org_member(organization_id));
revoke update, delete on public.notes_and_attachments from authenticated;
grant insert on public.notes_and_attachments to authenticated;

-- Payments are deliberately read-only until the payment posting RPC is available.
-- Preserve SELECT grants/policies for all the locked tables above.

comment on table public.inventory_movements is
  'Append-only stock ledger. Client writes are revoked; use audited transactional RPCs.';
comment on table public.sales is
  'Client writes are revoked until atomic sale posting and stock reservation RPCs exist.';
comment on table public.payroll_accruals is
  'Sensitive payroll data. Client writes are revoked pending audited payroll RPCs.';
comment on table public.audit_events is
  'Append-only audit trail. Client writes are revoked; trusted triggers/functions only.';
