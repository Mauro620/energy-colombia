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
