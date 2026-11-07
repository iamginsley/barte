-- Minimal stand-in for what Nhost provides, so the migrations run on plain Postgres.
-- Used only by scripts/test-migrations.sh; never applied to a real project.
create schema auth;
create table auth.users (id uuid primary key, display_name text);
