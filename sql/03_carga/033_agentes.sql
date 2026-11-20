-- Maestro de operadores: ListadoAgentes de la API XM. 5 codigos repetidos: queda la fila OPERACION mas reciente (S-05).
BEGIN;
SELECT control.iniciar_lote('xm_ListadoAgentes', 'energia.agente') AS lote \gset
TRUNCATE staging.stg_agente;
\copy staging.stg_agente FROM '/stage/agente.csv' WITH (FORMAT csv, HEADER true)

WITH base AS (
  SELECT s.*, CASE
      WHEN upper(btrim(code)) !~ '^[A-Z0-9]{4}$' THEN 'RN05'
      WHEN upper(btrim(state)) NOT IN ('OPERACION', 'INACTIVO') THEN 'RN15'
      WHEN control.a_fecha(operstartdate) IS NULL OR btrim(coalesce(name, '')) = '' OR btrim(coalesce(activity, '')) = '' THEN 'RN18'
    END AS regla
  FROM staging.stg_agente s),
rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla, 'agente invalido', to_jsonb(b) - 'regla' FROM base b WHERE regla IS NOT NULL RETURNING 1),
elegidas AS (
  SELECT b.*, row_number() OVER (PARTITION BY upper(btrim(code))
         ORDER BY (upper(btrim(state)) = 'OPERACION') DESC, control.a_fecha(operstartdate) DESC, fila_origen DESC) AS rn
  FROM base b WHERE regla IS NULL),
up AS (
  INSERT INTO energia.agente (codigo_sic, nombre, actividad, estado, fecha_inicio_operacion)
  SELECT upper(btrim(code)), upper(btrim(name)), upper(btrim(activity)), upper(btrim(state))::energia.estado_agente, control.a_fecha(operstartdate)
  FROM elegidas WHERE rn = 1
  ON CONFLICT (codigo_sic) DO UPDATE SET nombre = EXCLUDED.nombre, actividad = EXCLUDED.actividad, estado = EXCLUDED.estado,
      fecha_inicio_operacion = EXCLUDED.fecha_inicio_operacion
    WHERE (energia.agente.nombre, energia.agente.actividad, energia.agente.estado, energia.agente.fecha_inicio_operacion)
          IS DISTINCT FROM (EXCLUDED.nombre, EXCLUDED.actividad, EXCLUDED.estado, EXCLUDED.fecha_inicio_operacion)
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM staging.stg_agente) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;
