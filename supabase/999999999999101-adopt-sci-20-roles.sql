-- Adopt SCI-20 on databases that already ran the pre-SCI-20 bootstrap file.
-- This file is intentionally additive: the bootstrap migration is immutable once
-- PostgreSQL has initialized its data directory.
alter table public.profiles alter column team_id drop not null;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'name'
  ) then
    insert into public.profiles (id, email, name, role, team_id)
    values (
      new.id,
      new.email,
      new.email,
      (case when not exists (select 1 from public.profiles) then 'team_lead' else 'employee' end)::public.app_role,
      case
        when (new.raw_user_meta_data ->> 'team_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          and exists (select 1 from public.teams where id = (new.raw_user_meta_data ->> 'team_id')::uuid)
        then (new.raw_user_meta_data ->> 'team_id')::uuid
        else null
      end
    );
  else
    insert into public.profiles (id, email, role, team_id)
    values (
      new.id,
      new.email,
      (case when not exists (select 1 from public.profiles) then 'team_lead' else 'employee' end)::public.app_role,
      case
        when (new.raw_user_meta_data ->> 'team_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          and exists (select 1 from public.teams where id = (new.raw_user_meta_data ->> 'team_id')::uuid)
        then (new.raw_user_meta_data ->> 'team_id')::uuid
        else null
      end
    );
  end if;
  return new;
end;
$$;

create or replace function public.current_team_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select team_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_team_lead()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role = 'team_lead'::public.app_role from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.select_team(new_team_id uuid)
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

create or replace function public.create_team(team_name text)
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

drop function if exists public.create_initial_team(text);

grant select on public.teams to anon;
grant execute on function public.select_team(uuid) to authenticated;
grant execute on function public.create_team(text) to authenticated;

drop policy if exists "Team leads can view every team" on public.teams;
drop policy if exists "Team leads manage teams" on public.teams;
drop policy if exists "Anyone can view teams for registration" on public.teams;
drop policy if exists "Team leads create teams" on public.teams;
drop policy if exists "Team leads manage their team" on public.teams;
drop policy if exists "Users can view their visible colleagues" on public.profiles;
drop policy if exists "Team leads manage profiles" on public.profiles;
drop policy if exists "Users can view their profile and colleagues" on public.profiles;
drop policy if exists "Team leads change colleague roles" on public.profiles;
drop policy if exists "Manage visible projects" on public.projects;
drop policy if exists "Team leads manage their projects" on public.projects;

create policy "Anyone can view teams for registration" on public.teams for select using (true);
create policy "Team leads create teams" on public.teams for insert to authenticated with check (public.is_team_lead());
create policy "Team leads manage their team" on public.teams for update to authenticated using (id = public.current_team_id() and public.is_team_lead()) with check (id = public.current_team_id() and public.is_team_lead());
create policy "Users can view their profile and colleagues" on public.profiles for select to authenticated using (id = auth.uid() or (team_id is not null and team_id = public.current_team_id()));
create policy "Team leads change colleague roles" on public.profiles for update to authenticated using (id <> auth.uid() and team_id = public.current_team_id() and public.is_team_lead()) with check (team_id = public.current_team_id() and public.is_team_lead());
create policy "Team leads manage their projects" on public.projects for all to authenticated using (public.is_team_lead() and team_id = public.current_team_id()) with check (public.is_team_lead() and team_id = public.current_team_id());
