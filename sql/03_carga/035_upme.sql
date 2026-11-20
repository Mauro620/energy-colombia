-- UPME mensual (D09): periodo = dia 1; porcentaje_participacion NO pasa al modelo (vista). El ultimo mes publicado queda parcial.
BEGIN;
SELECT control.iniciar_lote('socrata_tq63-itzr', 'energia.generacion_mensual_upme') AS lote \gset
TRUNCATE staging.stg_upme;
\copy staging.stg_upme FROM '/stage/upme.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE tmp_upme ON COMMIT DROP AS
SELECT CASE WHEN control.a_numero(ano) IS NOT NULL AND control.a_numero(mes) BETWEEN 1 AND 12 AND control.a_numero(ano) BETWEEN 1900 AND 2200
            THEN make_date(control.a_numero(ano)::int, control.a_numero(mes)::int, 1) END AS periodo,
       upper(btrim(fuente)) AS fuente, control.a_numero(promedio_mensual_gwh) AS promedio, control.a_numero(maximo_gwh) AS maximo,
       control.a_numero(minimo_gwh) AS minimo, control.a_numero(generacion_total_gwh) AS total, fila_origen,
       CASE
         WHEN control.a_numero(ano) IS NULL OR control.a_numero(mes) IS NULL OR coalesce(btrim(fuente), '') = ''
              OR control.a_numero(promedio_mensual_gwh) IS NULL OR control.a_numero(maximo_gwh) IS NULL
              OR control.a_numero(minimo_gwh) IS NULL OR control.a_numero(generacion_total_gwh) IS NULL THEN 'RN18'
         WHEN control.a_numero(mes) NOT BETWEEN 1 AND 12 OR control.a_numero(ano) NOT BETWEEN 1900 AND 2200 THEN 'RN06'
         WHEN control.a_numero(promedio_mensual_gwh) < 0 OR control.a_numero(maximo_gwh) < 0 OR control.a_numero(minimo_gwh) < 0
              OR control.a_numero(generacion_total_gwh) < 0 OR control.a_numero(minimo_gwh) > control.a_numero(maximo_gwh) THEN 'RN01'
       END AS regla,
       to_jsonb(s) AS registro
FROM staging.stg_upme s;

INSERT INTO energia.fuente_energetica (nombre, en_upme) SELECT DISTINCT fuente, true FROM tmp_upme WHERE regla IS NULL
  ON CONFLICT (nombre) DO UPDATE SET en_upme = true WHERE NOT energia.fuente_energetica.en_upme;

WITH rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla, 'fila UPME invalida', registro FROM tmp_upme WHERE regla IS NOT NULL RETURNING 1),
elegidas AS (
  SELECT t.*, row_number() OVER (PARTITION BY periodo, fuente ORDER BY fila_origen DESC) AS rn,
         (periodo = max(periodo) OVER ()) AS es_ultimo
  FROM tmp_upme t WHERE regla IS NULL),
up AS (
  INSERT INTO energia.generacion_mensual_upme (periodo, fuente_energetica_id, promedio_mensual_gwh, maximo_gwh, minimo_gwh, generacion_total_gwh, parcial)
  SELECT e.periodo, f.fuente_energetica_id, e.promedio, e.maximo, e.minimo, e.total, e.es_ultimo
  FROM elegidas e JOIN energia.fuente_energetica f ON f.nombre = e.fuente WHERE e.rn = 1
  ON CONFLICT (periodo, fuente_energetica_id) DO UPDATE SET promedio_mensual_gwh = EXCLUDED.promedio_mensual_gwh,
      maximo_gwh = EXCLUDED.maximo_gwh, minimo_gwh = EXCLUDED.minimo_gwh, generacion_total_gwh = EXCLUDED.generacion_total_gwh, parcial = EXCLUDED.parcial
    WHERE (energia.generacion_mensual_upme.promedio_mensual_gwh, energia.generacion_mensual_upme.maximo_gwh, energia.generacion_mensual_upme.minimo_gwh,
           energia.generacion_mensual_upme.generacion_total_gwh, energia.generacion_mensual_upme.parcial)
          IS DISTINCT FROM (EXCLUDED.promedio_mensual_gwh, EXCLUDED.maximo_gwh, EXCLUDED.minimo_gwh, EXCLUDED.generacion_total_gwh, EXCLUDED.parcial)
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM tmp_upme) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;
