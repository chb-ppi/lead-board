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
    case when not exists (select 1 from public.profiles) then 'team_lead' else 'employee' end,
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
