#!/usr/bin/env bash
set -euo pipefail

container="sci-25-migration-$$"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --rm --name "$container" \
  -e POSTGRES_PASSWORD=test-password \
  -e JWT_SECRET=test-jwt-secret \
  supabase/postgres:15.1.0.147 >/dev/null

for _ in {1..30}; do
  if [ "$(docker exec "$container" psql -U postgres -d postgres -Atc "select to_regclass('auth.users') is not null and exists (select 1 from pg_event_trigger where evtname = 'graphql_watch_ddl')" 2>/dev/null)" = "t" ]; then
    break
  fi
  sleep 1
done
# The image briefly restarts PostgreSQL after its bundled migrations finish.
sleep 5
test "$(docker exec "$container" psql -U postgres -d postgres -Atc "select to_regclass('auth.users') is not null and exists (select 1 from pg_event_trigger where evtname = 'graphql_watch_ddl')")" = "t"

# The optional PostgREST and GraphQL DDL listeners are still initializing in
# this disposable image. They are unrelated to the application migration.
docker exec "$container" bash -c \
  "PGPASSWORD=test-password psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c 'alter event trigger pgrst_ddl_watch disable; alter event trigger pgrst_drop_watch disable; alter event trigger graphql_watch_ddl disable; alter event trigger graphql_watch_drop disable;'" \
  >/dev/null

# Recreate a deployed SCI-20 volume, including SCI-19's invitation schema.
git show 02ae21f^:supabase/99999999999998-roles-and-teams.sql |
  docker exec -i "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres >/dev/null

# Apply the real SCI-19 migration, including its invitation access policies.
git show 7d52d06:supabase/99999999999999-z-employee-invitations.sql |
  docker exec -i "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres >/dev/null

# This pre-migration account models an existing assignment that must survive.
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL' >/dev/null
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'legacy@example.test', '{}'::jsonb);
SQL

docker cp supabase/999999999999100-fix-project-trigger-runtime.sql "$container":/tmp/100.sql
docker cp supabase/999999999999101-adopt-sci-20-roles.sql "$container":/tmp/101.sql
docker cp supabase/999999999999102-account-management.sql "$container":/tmp/102.sql
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/100.sql >/dev/null
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/101.sql >/dev/null
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/101.sql >/dev/null
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/102.sql >/dev/null
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/102.sql >/dev/null

docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL' >/dev/null
do $$
declare
  legacy_team uuid;
  customer uuid;
begin
  select team_id into legacy_team
  from public.profiles
  where id = '11111111-1111-1111-1111-111111111111';
  if legacy_team is null then
    raise exception 'the legacy team assignment was lost';
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    '22222222-2222-2222-2222-222222222222',
    'new-account@example.test',
    jsonb_build_object('team_id', legacy_team::text)
  );
  if not exists (
    select 1 from public.profiles
    where id = '22222222-2222-2222-2222-222222222222'
      and role = 'employee'::public.app_role
      and team_id = legacy_team
      and name = 'new-account@example.test'
      and not must_change_password
  ) then
    raise exception 'the new account did not retain SCI-19 initialization';
  end if;

  insert into public.customers (team_id, name)
  values (legacy_team, 'Migration customer')
  returning id into customer;
end;
$$;
SQL

# Verify SCI-22 project management and employee reads through RLS, rather than
# as postgres (which bypasses row-level policies).
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL' >/dev/null
update public.profiles
set must_change_password = true
where id = '22222222-2222-2222-2222-222222222222';

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
insert into public.projects (team_id, customer_id, name)
select team_id, (select id from public.customers where name = 'Migration customer'), 'Lead-created project'
from public.profiles where id = '11111111-1111-1111-1111-111111111111';
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
do $$
begin
  if not exists (
    select 1 from public.profiles where id = '22222222-2222-2222-2222-222222222222'
  ) then
    raise exception 'initial-password lock no longer permits the employee self-read';
  end if;

  if exists (select 1 from public.projects where name = 'Lead-created project') then
    raise exception 'initial-password lock no longer protects employee reads';
  end if;
end;
$$;
commit;

update public.profiles
set must_change_password = false
where id = '22222222-2222-2222-2222-222222222222';

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
do $$
begin
  if not exists (select 1 from public.projects where name = 'Lead-created project') then
    raise exception 'employee cannot read their team project';
  end if;

  begin
    insert into public.projects (team_id, customer_id, name)
    select team_id, (select id from public.customers where name = 'Migration customer'), 'Employee-created project'
    from public.profiles where id = '22222222-2222-2222-2222-222222222222';
    raise exception 'employee was able to create a project';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
commit;
SQL

# SCI-21 account deactivation must revoke data access and prevent a client from
# altering account status directly.
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL' >/dev/null
update public.profiles
set is_active = false
where id = '22222222-2222-2222-2222-222222222222';

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
do $$
begin
  if exists (select 1 from public.projects where name = 'Lead-created project') then
    raise exception 'deactivated employee can still read team data';
  end if;
  begin
    update public.profiles set is_active = true where id = auth.uid();
    raise exception 'client can reactivate its own account';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
commit;
SQL
