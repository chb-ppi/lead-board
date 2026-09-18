do $$ begin
  create role anon nologin;
exception when duplicate_object then null;
end $$;

do $$ begin
  create role authenticated nologin;
exception when duplicate_object then null;
end $$;

do $$ begin
  create role authenticator noinherit login password 'authenticator';
exception when duplicate_object then null;
end $$;
grant anon, authenticated to authenticator;
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
