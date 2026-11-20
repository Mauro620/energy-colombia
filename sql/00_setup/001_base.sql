-- Idempotente. CREATE DATABASE no admite IF NOT EXISTS: se usa \gexec.
SELECT 'CREATE DATABASE energia_db'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'energia_db')\gexec

\connect energia_db

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
