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
  team_id uuid references public.teams (id),
  created_at timestamptz not null default now()
);

create function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_team_id uuid;
begin
  begin
    requested_team_id := nullif(new.raw_user_meta_data ->> 'team_id', '')::uuid;
  exception when invalid_text_representation then
    requested_team_id := null;
  end;

  insert into public.profiles (id, email, role, team_id)
  values (
    new.id,
    new.email,
    (case when not exists (select 1 from public.profiles) then 'team_lead' else 'employee' end)::public.app_role,
    case when exists (select 1 from public.teams where id = requested_team_id) then requested_team_id else null end
  );
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

create trigger projects_same_team before insert or update on public.projects
for each row execute function public.enforce_team_relationships();
create trigger assignments_same_team before insert or update on public.employee_assignments
for each row execute function public.enforce_team_relationships();
create trigger engagements_same_team before insert or update on public.engagements
for each row execute function public.enforce_team_relationships();
create trigger offers_same_team before insert or update on public.offers
for each row execute function public.enforce_team_relationships();

create function public.select_team(new_team_id uuid)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  new_profile public.profiles;
begin
  if auth.uid() is null or not exists (select 1 from public.teams where id = new_team_id) then
    raise exception 'A valid team must be selected';
  end if;
  update public.profiles
  set team_id = new_team_id
  where id = auth.uid() and team_id is null
  returning * into new_profile;
  if new_profile is null then
    raise exception 'A team is already assigned';
  end if;
  return new_profile;
end;
$$;

create function public.create_team(team_name text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  new_team public.teams;
  new_profile public.profiles;
begin
  if auth.uid() is null or not public.is_team_lead() then
    raise exception 'Only a team lead can create a team';
  end if;
  insert into public.teams (name) values (team_name) returning * into new_team;
  update public.profiles
  set team_id = new_team.id
  where id = auth.uid() and team_id is null
  returning * into new_profile;
  return coalesce(new_profile, (select p from public.profiles p where p.id = auth.uid()));
end;
$$;

grant usage on schema public to anon, authenticated;
grant select on public.teams to anon;
grant select, insert, update on public.teams, public.profiles, public.customers, public.projects, public.employee_assignments, public.engagements, public.offers to authenticated;
grant execute on function public.select_team(uuid) to authenticated;
grant execute on function public.create_team(text) to authenticated;

alter table public.teams enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.projects enable row level security;
alter table public.employee_assignments enable row level security;
alter table public.engagements enable row level security;
alter table public.offers enable row level security;

create policy "Anyone can view teams for registration" on public.teams for select using (true);
create policy "Team leads create teams" on public.teams for insert to authenticated with check (public.is_team_lead());
create policy "Team leads manage their team" on public.teams for update to authenticated using (id = public.current_team_id() and public.is_team_lead()) with check (id = public.current_team_id() and public.is_team_lead());
create policy "Users can view their profile and colleagues" on public.profiles for select to authenticated using (id = auth.uid() or (team_id is not null and team_id = public.current_team_id()));
create policy "Team leads change colleague roles" on public.profiles for update to authenticated using (id <> auth.uid() and team_id = public.current_team_id() and public.is_team_lead()) with check (team_id = public.current_team_id() and public.is_team_lead());

create policy "Visible customers" on public.customers for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible customers" on public.customers for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
create policy "Visible projects" on public.projects for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Team leads manage their projects" on public.projects for all to authenticated using (public.is_team_lead() and team_id = public.current_team_id()) with check (public.is_team_lead() and team_id = public.current_team_id());
create policy "Visible assignments" on public.employee_assignments for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible assignments" on public.employee_assignments for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
create policy "Visible engagements" on public.engagements for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible engagements" on public.engagements for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
create policy "Visible offers" on public.offers for select to authenticated using (public.is_team_lead() or team_id = public.current_team_id());
create policy "Manage visible offers" on public.offers for all to authenticated using (public.is_team_lead() or team_id = public.current_team_id()) with check (public.is_team_lead() or team_id = public.current_team_id());
