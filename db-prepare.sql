-- ============================================================
-- db-prepare.sql
-- Prerequisites required BEFORE GoTrue (auth) container runs its
-- migrations for the FIRST time on a fresh database.
--
-- The bundled gotrue-migrations are TRUNCATED: they only contain
-- CREATE TABLE statements and expect the following objects to be
-- pre-created by the deployer:
--   1. schema "auth"
--   2. extension pgcrypto
--   3. role "postgres" (migrations contain hardcoded GRANT ... TO postgres,
--      while this container's superuser is named "supabase")
--
-- Idempotent: safe to run multiple times, at any stage.
-- Usage:  docker cp db-prepare.sql supabase-db:/tmp/db-prepare.sql
--         docker exec supabase-db psql -U supabase -d postgres -v ON_ERROR_STOP=1 -f /tmp/db-prepare.sql
-- ============================================================

CREATE SCHEMA IF NOT EXISTS auth;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        CREATE ROLE postgres SUPERUSER;
    END IF;
END
$$;
