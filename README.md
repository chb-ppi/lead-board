# Lead Board

Lead Board is a React MVP with a self-hosted Supabase stack for local accounts
and persistent application data.

## Start locally

1. Copy the local development configuration: `cp .env.example .env`
2. Start the complete stack: `docker compose up --build`
3. Open `http://localhost:3000` and create an account or sign in.

The frontend talks to Supabase through Kong at `http://localhost:8000`. Supabase
data is stored in the named `supabase-db` Docker volume and survives container
restarts. To remove all local data deliberately, run `docker compose down -v`.

`JWT_SECRET`, `ANON_KEY`, and database passwords in `.env.example` are local
development values only. Replace them with separately managed values before any
non-local deployment; do not commit the resulting `.env` file.

## Services

- `web`: React application served by Caddy on port 3000
- `db`: Supabase PostgreSQL with persistent storage
- `auth`: Supabase GoTrue for local email/password accounts
- `rest`: PostgREST API for future data access
- `kong`: Supabase API gateway on port 8000

Supabase creates its service roles through its own database migrations. A final
local migration assigns their passwords from `POSTGRES_PASSWORD`, after the
built-in migrations have completed. Domain tables and the team-lead role model
are intentionally left to their respective feature issues.
