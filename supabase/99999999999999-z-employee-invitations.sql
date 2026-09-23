alter table public.profiles
  add column name text,
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
  insert into public.profiles (id, email, name, team_id)
  values (new.id, new.email, new.email, '00000000-0000-0000-0000-000000000001');
  return new;
end;
$$;

create unique index profiles_email_lower_key on public.profiles (lower(email));

create function public.email_is_in_use(candidate_email text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where lower(email) = lower(candidate_email)
  );
$$;

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

grant execute on function public.email_is_in_use(text) to authenticated;
grant execute on function public.complete_initial_password_change() to authenticated;

drop policy "Team leads can view every team" on public.teams;
drop policy "Team leads manage teams" on public.teams;
drop policy "Users can view their visible colleagues" on public.profiles;
drop policy "Team leads manage profiles" on public.profiles;

create policy "Users can view their team" on public.teams for select to authenticated using (id = public.current_team_id());
create policy "Users can view their colleagues" on public.profiles for select to authenticated using (team_id = public.current_team_id());
