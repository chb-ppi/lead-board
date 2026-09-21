\getenv postgres_password POSTGRES_PASSWORD

alter role authenticator password :'postgres_password';
alter role supabase_auth_admin password :'postgres_password';
