alter table public.profiles
  add column name text,
  add column email_normalized text generated always as (lower(email)) stored,
  add column must_change_password boolean not null default false;

update public.profiles set name = email where name is null;

alter table public.profiles
  alter column name set not null,
  add constraint profiles_name_not_blank check (char_length(trim(name)) > 0);

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

create unique index profiles_email_normalized_key on public.profiles (email_normalized);

create function public.complete_initial_password_change()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.profiles
  set must_change_password = false
  where id = auth.uid() and must_change_password;
end;
$$;

grant execute on function public.complete_initial_password_change() to authenticated;
