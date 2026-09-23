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
  if [ "$(docker exec "$container" psql -U postgres -d postgres -Atc "select to_regclass('auth.users') is not null" 2>/dev/null)" = "t" ]; then
    break
  fi
  sleep 1
done
test "$(docker exec "$container" psql -U postgres -d postgres -Atc "select to_regclass('auth.users') is not null")" = "t"

# Recreate the schema that was already present in deployed SCI-20 volumes.
git show 02ae21f^:supabase/99999999999998-roles-and-teams.sql |
  docker exec -i "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres >/dev/null

# This pre-migration account models an existing assignment that must survive.
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL' >/dev/null
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'legacy@example.test', '{}'::jsonb);
SQL

docker cp supabase/999999999999100-fix-project-trigger-runtime.sql "$container":/tmp/100.sql
docker cp supabase/999999999999101-adopt-sci-20-roles.sql "$container":/tmp/101.sql
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/100.sql >/dev/null
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/101.sql >/dev/null
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/101.sql >/dev/null

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
  ) then
    raise exception 'the new account was not created with the requested team';
  end if;

  insert into public.customers (team_id, name)
  values (legacy_team, 'Migration customer')
  returning id into customer;
  insert into public.projects (team_id, customer_id, name)
  values (legacy_team, customer, 'Migration project');
end;
$$;
SQL
