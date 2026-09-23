create or replace function public.enforce_team_relationships()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  new_row jsonb := to_jsonb(new);
begin
  if tg_table_name = 'projects' and not exists (
    select 1
    from public.customers
    where id = (new_row ->> 'customer_id')::uuid
      and team_id = (new_row ->> 'team_id')::uuid
  ) then
    raise exception 'Project and customer must belong to the same team';
  end if;

  if tg_table_name = 'employee_assignments' and not exists (
    select 1
    from public.projects
    where id = (new_row ->> 'project_id')::uuid
      and team_id = (new_row ->> 'team_id')::uuid
  ) then
    raise exception 'Assignment and project must belong to the same team';
  end if;

  if tg_table_name = 'employee_assignments' and not exists (
    select 1
    from public.profiles
    where id = (new_row ->> 'employee_id')::uuid
      and team_id = (new_row ->> 'team_id')::uuid
  ) then
    raise exception 'Assignment and employee must belong to the same team';
  end if;

  if tg_table_name = 'engagements' and not exists (
    select 1
    from public.employee_assignments
    where id = (new_row ->> 'assignment_id')::uuid
      and team_id = (new_row ->> 'team_id')::uuid
  ) then
    raise exception 'Engagement and assignment must belong to the same team';
  end if;

  if tg_table_name = 'offers' and not exists (
    select 1
    from public.projects
    where id = (new_row ->> 'project_id')::uuid
      and team_id = (new_row ->> 'team_id')::uuid
  ) then
    raise exception 'Offer and project must belong to the same team';
  end if;

  if tg_table_name = 'offers'
    and (new_row ->> 'employee_id') is not null
    and not exists (
      select 1
      from public.profiles
      where id = (new_row ->> 'employee_id')::uuid
        and team_id = (new_row ->> 'team_id')::uuid
    ) then
    raise exception 'Offer and employee must belong to the same team';
  end if;

  return new;
end;
$$;

drop policy if exists "Manage visible projects" on public.projects;
drop policy if exists "Team leads manage their projects" on public.projects;
create policy "Team leads manage their projects" on public.projects
for all to authenticated
using (public.is_team_lead() and team_id = public.current_team_id())
with check (public.is_team_lead() and team_id = public.current_team_id());
