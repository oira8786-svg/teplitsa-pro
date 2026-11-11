-- ТЕПЛИЦА PRO / 005_task_assignee_tenant_integrity.sql
-- A task assignee must belong to the same organization as the task.
-- This constraint complements (but does not replace) active-membership checks
-- that must be performed by future task RPCs.

alter table public.tasks
  add constraint tasks_assigned_user_same_org_fk
  foreign key (organization_id, assigned_user_id)
  references public.memberships(organization_id, user_id);

create index tasks_org_assigned_user_idx
  on public.tasks(organization_id, assigned_user_id)
  where assigned_user_id is not null;
