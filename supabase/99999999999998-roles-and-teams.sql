create type public.app_role as enum ('team_lead', 'employee');

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(trim(name)) > 0),
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  role public.app_role not null default 'employee',
  team_id uuid not null references public.teams (id),
  created_at timestamptz not null default now()
);

insert into public.teams (id, name)
values ('00000000-0000-0000-0000-000000000001', 'Nicht zugeordnet');

create function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, team_id)
  values (new.id, new.email, '00000000-0000-0000-0000-000000000001');
  return new;
end;
$$;

create trigger create_profile_after_signup
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id),
  name text not null check (char_length(trim(name)) > 0),
  created_at timestamptz not null default now()
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id),
  customer_id uuid not null references public.customers (id),
  name text not null check (char_length(trim(name)) > 0),
  created_at timestamptz not null default now()
);

create table public.employee_assignments (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id),
  project_id uuid not null references public.projects (id),
  employee_id uuid not null references public.profiles (id),
  starts_on date not null,
  ends_on date,
  available_days numeric(8, 2) not null check (available_days >= 0),
  check (ends_on is null or ends_on >= starts_on),
  created_at timestamptz not null default now()
);

create table public.engagements (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id),
  assignment_id uuid not null references public.employee_assignments (id),
  starts_on date not null,
  ends_on date,
  offered_days numeric(8, 2) not null check (offered_days >= 0),
  daily_rate numeric(10, 2) not null check (daily_rate >= 0),
  check (ends_on is null or ends_on >= starts_on),
  created_at timestamptz not null default now()
);

create table public.offers (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id),
  project_id uuid not null references public.projects (id),
  employee_id uuid references public.profiles (id),
  status text not null default 'draft' check (status in ('draft', 'sent', 'negotiation', 'accepted', 'rejected')),
  offered_days numeric(8, 2) not null check (offered_days >= 0),
  daily_rate numeric(10, 2) not null check (daily_rate >= 0),
  created_at timestamptz not null default now()
);

create function public.current_team_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select team_id from public.profiles where id = auth.uid()
$$;

create function public.is_team_lead()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role = 'team_lead' from public.profiles where id = auth.uid()), false)
$$;

create function public.enforce_team_relationships()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'projects' and not exists (
    select 1 from public.customers where id = new.customer_id and team_id = new.team_id
  ) then
    raise exception 'Project and customer must belong to the same team';
  end if;

  if tg_table_name = 'employee_assignments' and not exists (
    select 1 from public.projects where id = new.project_id and team_id = new.team_id
  ) then
    raise exception 'Assignment and project must belong to the same team';
  end if;

  if tg_table_name = 'employee_assignments' and not exists (
    select 1 from public.profiles where id = new.employee_id and team_id = new.team_id
  ) then
    raise exception 'Assignment and employee must belong to the same team';
  end if;

  if tg_table_name = 'engagements' and not exists (
    select 1 from public.employee_assignments where id = new.assignment_id and team_id = new.team_id
  ) then
    raise exception 'Engagement and assignment must belong to the same team';
  end if;

  if tg_table_name = 'offers' and not exists (
    select 1 from public.projects where id = new.project_id and team_id = new.team_id
  ) then
    raise exception 'Offer and project must belong to the same team';
  end if;

  if tg_table_name = 'offers' and new.employee_id is not null and not exists (
    select 1 from public.profiles where id = new.employee_id and team_id = new.team_id
  ) then
    raise exception 'Offer and employee must belong to the same team';
  end if;

  return new;
end;
$$;

create trigger projects_same_team before insert or update on public.projects
for each row execute function public.enforce_team_relationships();
create trigger assignments_same_team before insert or update on public.employee_assignments
for each row execute function public.enforce_team_relationships();
create trigger engagements_same_team before insert or update on public.engagements
for each row execute function public.enforce_team_relationships();
create trigger offers_same_team before insert or update on public.offers
for each row execute function public.enforce_team_relationships();

create function public.create_initial_team(team_name text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  new_team public.teams;
  new_profile public.profiles;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'employee'
      and team_id = '00000000-0000-0000-0000-000000000001'
  ) or exists (select 1 from public.profiles where role = 'team_lead') then
    raise exception 'Initial team can only be created by the first unassigned user';
  end if;

  insert into public.teams (name) values (team_name) returning * into new_team;
  update public.profiles
  set role = 'team_lead', team_id = new_team.id
  where id = auth.uid()
  returning * into new_profile;
  return new_profile;
end;
$$;

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.teams, public.profiles, public.customers, public.projects, public.employee_assignments, public.engagements, public.offers to authenticated;
grant execute on function public.create_initial_team(text) to authenticated;

alter table public.teams enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.projects enable row level security;
alter table public.employee_assignments enable row level security;
alter table public.engagements enable row level security;
alter table public.offers enable row level security;

create policy "Team leads can view every team" on public.teams for select to authenticated using (public.is_team_lead() or id = public.current_team_id());
create policy "Team leads manage teams" on public.teams for all to authenticated using (public.is_team_lead()) with check (public.is_team_lead());
create policy "Users can view their visible colleagues" on public.profiles for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Team leads manage profiles" on public.profiles for all to authenticated using (public.is_team_lead()) with check (public.is_team_lead());

create policy "Visible customers" on public.customers for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible customers" on public.customers for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
create policy "Visible projects" on public.projects for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible projects" on public.projects for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
create policy "Visible assignments" on public.employee_assignments for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible assignments" on public.employee_assignments for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
create policy "Visible engagements" on public.engagements for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible engagements" on public.engagements for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
create policy "Visible offers" on public.offers for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible offers" on public.offers for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
