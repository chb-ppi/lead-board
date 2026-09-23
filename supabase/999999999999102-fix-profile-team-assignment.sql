-- Use PostgreSQL's UUID parser so account creation can retain an existing team.
-- The regular-expression check in earlier bootstrap code was not reliable on
-- deployed legacy volumes and silently left the profile without a team.
create or replace function public.create_profile_for_new_user()
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
      case when exists (select 1 from public.teams where id = requested_team_id) then requested_team_id else null end
    );
  else
    insert into public.profiles (id, email, role, team_id)
    values (
      new.id,
      new.email,
      (case when not exists (select 1 from public.profiles) then 'team_lead' else 'employee' end)::public.app_role,
      case when exists (select 1 from public.teams where id = requested_team_id) then requested_team_id else null end
    );
  end if;
  return new;
end;
$$;
