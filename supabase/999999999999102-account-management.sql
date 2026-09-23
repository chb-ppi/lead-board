-- Account controls are kept in the profile, while GoTrue enforces the login ban.
alter table public.profiles
  add column if not exists is_active boolean not null default true,
  add column if not exists last_reset_requested_at timestamptz,
  add column if not exists reset_status text not null default 'none'
    check (reset_status in ('none', 'sent', 'failed'));

create or replace function public.is_active_account()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_active from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.has_completed_initial_password_change()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  access_allowed boolean;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'must_change_password'
  ) then
    select is_active into access_allowed from public.profiles where id = auth.uid();
  else
    execute 'select is_active and not must_change_password from public.profiles where id = auth.uid()'
      into access_allowed;
  end if;
  return coalesce(access_allowed, false);
end;
$$;

-- Do not allow client-side profile updates to impersonate the service endpoint.
revoke update on public.profiles from authenticated;
grant update (team_id, role) on public.profiles to authenticated;

drop policy if exists "Users can view their profile and colleagues" on public.profiles;
create policy "Users can view their profile and colleagues" on public.profiles for select to authenticated using (
  public.is_active_account()
  and (id = auth.uid() or (public.has_completed_initial_password_change() and team_id is not null and team_id = public.current_team_id()))
);

drop policy if exists "Team leads change colleague roles" on public.profiles;
create policy "Team leads change colleague roles" on public.profiles for update to authenticated using (
  public.is_active_account()
  and public.has_completed_initial_password_change()
  and id <> auth.uid()
  and team_id = public.current_team_id()
  and public.is_team_lead()
) with check (
  public.is_active_account()
  and public.has_completed_initial_password_change()
  and team_id = public.current_team_id()
  and public.is_team_lead()
);
