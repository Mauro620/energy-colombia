-- ENUM del modelo (RN15). Idempotente: CREATE TYPE no admite IF NOT EXISTS.
-- Dominios cerrados segun el perfil de las fuentes (hoja Dominios_ENUM del xlsx).
DO $$
DECLARE t record;
BEGIN
  FOR t IN SELECT * FROM (VALUES
      ('energia', 'estado_planta',   ARRAY['OPERACION', 'PRUEBAS']),
      ('energia', 'tipo_despacho',   ARRAY['DESPACHADO CENTRALMENTE', 'NO DESPACHADO CENTRALMENTE']),
      ('energia', 'estado_agente',   ARRAY['OPERACION', 'INACTIVO']),
      ('energia', 'estado_estacion', ARRAY['ACTIVA', 'SUSPENDIDA', 'EN MANTENIMIENTO']),
      ('control', 'estado_lote',     ARRAY['en_curso', 'ok', 'error'])
    ) v(esquema, nombre, valores)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_type ty JOIN pg_namespace n ON n.oid = ty.typnamespace
                   WHERE n.nspname = t.esquema AND ty.typname = t.nombre) THEN
      EXECUTE format('CREATE TYPE %I.%I AS ENUM (%s)', t.esquema, t.nombre,
                     (SELECT string_agg(quote_literal(x), ', ') FROM unnest(t.valores) x));
    END IF;
  END LOOP;
END $$;
