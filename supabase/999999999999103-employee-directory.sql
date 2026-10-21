-- Preserve a display name for existing accounts and allow the employee
-- directory to use the same server-side role and team rules as the app.
alter table public.profiles add column if not exists name text;
update public.profiles set name = email where name is null or trim(name) = '';
alter table public.profiles alter column name set not null;

drop policy if exists "Users can view their profile and colleagues" on public.profiles;
create policy "Users can view their profile and colleagues" on public.profiles
for select to authenticated using (
  id = auth.uid()
  or (
    public.has_completed_initial_password_change()
    and (
      public.is_team_lead()
      or (team_id is not null and team_id = public.current_team_id())
    )
  )
);
