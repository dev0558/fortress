-- ==========================================================================
-- FORTRESS - PostgreSQL Initialisation Script
-- ==========================================================================
-- This script runs once when the postgres container is first created.
-- It enables pgcrypto, creates application tables, seeds demo data,
-- and configures a least-privilege application role.
-- ==========================================================================

-- Enable pgcrypto for UUID generation and hashing utilities
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- --------------------------------------------------------------------------
-- Tables
-- --------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username    VARCHAR(64)  NOT NULL UNIQUE,
    role        VARCHAR(32)  NOT NULL DEFAULT 'readonly',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     VARCHAR(64)  NOT NULL,
    title       VARCHAR(256) NOT NULL,
    body        TEXT         NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_log (
    id          BIGSERIAL    PRIMARY KEY,
    actor       VARCHAR(64)  NOT NULL,
    action      VARCHAR(64)  NOT NULL,
    resource    VARCHAR(128) NOT NULL,
    detail      JSONB,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_notes_user_id    ON notes (user_id);
CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_actor      ON audit_log (actor);

-- --------------------------------------------------------------------------
-- Seed demo data
-- --------------------------------------------------------------------------

INSERT INTO users (username, role) VALUES
    ('admin',   'admin'),
    ('analyst', 'analyst'),
    ('viewer',  'readonly')
ON CONFLICT (username) DO NOTHING;

INSERT INTO notes (user_id, title, body) VALUES
    ('admin',   'Welcome',          'Welcome to the FORTRESS network segmentation lab.'),
    ('analyst', 'Investigation #1', 'Initial triage of perimeter alerts completed.')
ON CONFLICT DO NOTHING;

-- --------------------------------------------------------------------------
-- Least-privilege application role
-- --------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user WITH LOGIN PASSWORD 'change-me';
    END IF;
END
$$;

-- Revoke default public access and grant only what the application needs
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_user;

-- Table-level grants: read/write on users and notes, insert-only on audit_log
GRANT SELECT, INSERT, UPDATE ON users     TO app_user;
GRANT SELECT, INSERT, UPDATE ON notes     TO app_user;
GRANT SELECT, INSERT         ON audit_log TO app_user;

-- Sequence grants so INSERTs with serial/bigserial columns work
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
