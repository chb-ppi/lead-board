alter table public.profiles
  add column if not exists name text,
  add column if not exists email_normalized text generated always as (lower(email)) stored,
  add column if not exists must_change_password boolean not null default false;

update public.profiles set name = email where name is null;

alter table public.profiles
  alter column name set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_name_not_blank'
  ) then
    alter table public.profiles
      add constraint profiles_name_not_blank check (char_length(trim(name)) > 0);
  end if;
end;
$$;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, name, role, team_id)
  values (
    new.id,
    new.email,
    new.email,
    (case when not exists (select 1 from public.profiles) then 'team_lead' else 'employee' end)::public.app_role,
    case
      when (new.raw_user_meta_data ->> 'team_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and exists (select 1 from public.teams where id = (new.raw_user_meta_data ->> 'team_id')::uuid)
      then (new.raw_user_meta_data ->> 'team_id')::uuid
      else null
    end
  );
  return new;
end;
$$;

create unique index if not exists profiles_email_normalized_key
  on public.profiles (email_normalized);

create or replace function public.has_completed_initial_password_change()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select not must_change_password from public.profiles where id = auth.uid()),
    false
  )
$$;

drop policy if exists "Users can view their profile and colleagues" on public.profiles;
create policy "Users can view their profile and colleagues" on public.profiles for select to authenticated using (
  id = auth.uid()
  or (public.has_completed_initial_password_change() and team_id is not null and team_id = public.current_team_id())
);

drop policy if exists "Team leads change colleague roles" on public.profiles;
create policy "Team leads change colleague roles" on public.profiles for update to authenticated using (
  public.has_completed_initial_password_change()
  and id <> auth.uid()
  and team_id = public.current_team_id()
  and public.is_team_lead()
) with check (
  public.has_completed_initial_password_change()
  and team_id = public.current_team_id()
  and public.is_team_lead()
);

drop policy if exists "Visible customers" on public.customers;
create policy "Visible customers" on public.customers for select to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);
drop policy if exists "Manage visible customers" on public.customers;
create policy "Manage visible customers" on public.customers for all to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
) with check (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);

drop policy if exists "Visible projects" on public.projects;
create policy "Visible projects" on public.projects for select to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);
drop policy if exists "Manage visible projects" on public.projects;
create policy "Manage visible projects" on public.projects for all to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
) with check (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);

drop policy if exists "Visible assignments" on public.employee_assignments;
create policy "Visible assignments" on public.employee_assignments for select to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);
drop policy if exists "Manage visible assignments" on public.employee_assignments;
create policy "Manage visible assignments" on public.employee_assignments for all to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
) with check (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);

drop policy if exists "Visible engagements" on public.engagements;
create policy "Visible engagements" on public.engagements for select to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);
drop policy if exists "Manage visible engagements" on public.engagements;
create policy "Manage visible engagements" on public.engagements for all to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
) with check (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);

drop policy if exists "Visible offers" on public.offers;
create policy "Visible offers" on public.offers for select to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);
drop policy if exists "Manage visible offers" on public.offers;
create policy "Manage visible offers" on public.offers for all to authenticated using (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
) with check (
  public.has_completed_initial_password_change()
  and (public.is_team_lead() or team_id = public.current_team_id())
);

drop function if exists public.complete_initial_password_change();

create or replace function public.clear_initial_password_requirement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set must_change_password = false
  where id = new.id
    and must_change_password
    and old.encrypted_password is distinct from new.encrypted_password;
  return new;
end;
$$;

drop trigger if exists clear_initial_password_requirement on auth.users;
create trigger clear_initial_password_requirement
after update of encrypted_password on auth.users
for each row execute function public.clear_initial_password_requirement();
