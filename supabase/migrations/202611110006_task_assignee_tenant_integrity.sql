-- ТЕПЛИЦА PRO / 006_task_assignee_tenant_integrity.sql
-- A task assignee must belong to the same organization as the task.
-- This constraint complements (but does not replace) active-membership checks
-- performed by the task RPCs.

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'tasks_assigned_user_same_org_fk'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_assigned_user_same_org_fk
      foreign key (organization_id, assigned_user_id)
      references public.memberships(organization_id, user_id);
  end if;
end;
$$;

create index if not exists tasks_org_assigned_user_idx
  on public.tasks(organization_id, assigned_user_id)
  where assigned_user_id is not null;
