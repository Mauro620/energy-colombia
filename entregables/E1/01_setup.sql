-- Setup: base energia_db, extensiones y esquemas. Conectarse a la base postgres.
-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d <base> -f 01_setup.sql

-- ======================================================================
-- sql/00_setup/001_base.sql
-- ======================================================================
-- Idempotente. CREATE DATABASE no admite IF NOT EXISTS: se usa \gexec.
SELECT 'CREATE DATABASE energia_db'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'energia_db')\gexec

\connect energia_db

REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- ======================================================================
-- sql/00_setup/002_esquemas_extensiones.sql
-- ======================================================================
-- Esquemas y extensiones de energia_db. Idempotente. Ejecutar con: psql -v ON_ERROR_STOP=1 -f ...
-- staging = texto crudo aplanado; energia = modelo; control = cargas y cuarentena; analitica = solo vistas.
\connect energia_db

CREATE EXTENSION IF NOT EXISTS btree_gist;  -- EXCLUDE con igualdad de entero + solape de rango (ex_capacidad_vigencia)
CREATE EXTENSION IF NOT EXISTS unaccent;    -- claves de cruce geografico sin tildes (D05, DQ14)

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS energia;
CREATE SCHEMA IF NOT EXISTS control;
CREATE SCHEMA IF NOT EXISTS analitica;

-- upper + unaccent + trim + puntuacion a espacio. Declarada IMMUTABLE (unaccent con diccionario fijo no cambia)
-- para poder usarla en columnas GENERATED. 'Bogota, D.C' -> 'BOGOTA D C'.
CREATE OR REPLACE FUNCTION energia.normalizar_texto(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS $$
  SELECT btrim(regexp_replace(upper(public.unaccent('public.unaccent'::regdictionary, t)), '[[:punct:][:space:]]+', ' ', 'g'))
$$;
