# Lead Board

Lead Board is a React MVP with a self-hosted Supabase stack for local accounts
and persistent application data.

## Start locally

1. Copy the local development configuration: `cp .env.example .env`
2. Set `SERVICE_ROLE_KEY` to a `service_role` JWT signed with `JWT_SECRET`.
3. Configure the SMTP variables so Supabase Auth can deliver invitations.
4. Start the complete stack: `docker compose up --build`
5. Open `http://localhost:3000` and create an account or sign in.

The frontend talks to Supabase through Kong at `http://localhost:8000`. Supabase
data is stored in the named `supabase-db` Docker volume and survives container
restarts. To remove all local data deliberately, run `docker compose down -v`.

`JWT_SECRET`, `ANON_KEY`, and database passwords in `.env.example` are local
development values only. Replace them with separately managed values before any
non-local deployment; do not commit the resulting `.env` file.

## Services

- `web`: React application served by Caddy on port 3000
- `db`: Supabase PostgreSQL with persistent storage
- `auth`: Supabase GoTrue for local email/password accounts and invitations
- `rest`: PostgREST API for future data access
- `kong`: Supabase API gateway on port 8000

Supabase creates its service roles through its own database migrations. Local
migrations then assign their passwords and create the team, role, and MVP domain
tables. New users initially join the `Nicht zugeordnet` team. The first user
creates a team during onboarding and becomes its teamleitung. Teamleitungen can
invite employees only into their own team. The invitation API is a separate
internal service so the Supabase service-role key is never exposed to the
browser. Invited employees must set their own password before accessing the
application.
For a clean local database after updating migrations, run `docker compose down
-v` before starting the stack again.
