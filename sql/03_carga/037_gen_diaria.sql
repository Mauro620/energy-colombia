-- SIMEM E17D25 -> generacion_diaria_planta (D02-rev a). Solo plantas del listado de recursos; el resto a cuarentena (S-09).
-- Las ventanas del backfill se solapan en 2 dias: las filas repetidas son identicas y se omiten (ON CONFLICT).
-- 10 claves (planta, fecha) traen valores distintos: ambas filas van a cuarentena (S-08, H02).
BEGIN;
SELECT control.iniciar_lote('simem_E17D25', 'energia.generacion_diaria_planta') AS lote \gset
TRUNCATE staging.stg_gen_diaria;
\copy staging.stg_gen_diaria FROM '/stage/gen_diaria.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE tmp_diaria ON COMMIT DROP AS
SELECT p.planta_id, v.fecha, v.despacho, v.redespacho, v.real, s.fila_origen, r.regla, to_jsonb(s) AS registro
FROM staging.stg_gen_diaria s
LEFT JOIN energia.planta p ON p.codigo = upper(btrim(s.codigoplanta))
CROSS JOIN LATERAL (SELECT control.a_fecha(s.fecha) AS fecha, control.a_numero(s.generacionprogramadadespacho) AS despacho,
                           control.a_numero(s.generacionprogramadaredespacho) AS redespacho, control.a_numero(s.generacionrealestimada) AS real) v
CROSS JOIN LATERAL (SELECT CASE
    WHEN upper(btrim(s.codigoplanta)) !~ '^[A-Z0-9]{4}$' THEN 'RN05'
    WHEN v.fecha IS NULL OR v.despacho IS NULL OR v.redespacho IS NULL OR v.real IS NULL THEN 'RN18'
    WHEN v.despacho < 0 OR v.redespacho < 0 OR v.real < 0 THEN 'RN01'
    WHEN p.planta_id IS NULL THEN 'RN17'
  END AS regla) r;

WITH conflicto AS (  -- misma clave con valores distintos (RN19)
  SELECT planta_id, fecha FROM tmp_diaria WHERE regla IS NULL GROUP BY planta_id, fecha
  HAVING count(DISTINCT (despacho, redespacho, real)) > 1),
marcadas AS (
  SELECT t.*, CASE WHEN t.regla IS NULL AND c.planta_id IS NOT NULL THEN 'RN19' ELSE t.regla END AS regla_final
  FROM tmp_diaria t LEFT JOIN conflicto c ON c.planta_id = t.planta_id AND c.fecha = t.fecha),
rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla_final,
         CASE regla_final WHEN 'RN17' THEN 'planta que no esta en el listado de recursos' WHEN 'RN19' THEN 'misma (planta, fecha) con valores distintos'
              ELSE 'fila de generacion diaria invalida' END,
         registro
  FROM marcadas m WHERE regla_final IS NOT NULL RETURNING 1),
elegidas AS (
  SELECT m.*, row_number() OVER (PARTITION BY planta_id, fecha ORDER BY fila_origen DESC) AS rn FROM marcadas m WHERE regla_final IS NULL),
up AS (
  INSERT INTO energia.generacion_diaria_planta (planta_id, fecha, programada_despacho_kwh, programada_redespacho_kwh, real_estimada_kwh)
  SELECT planta_id, fecha, despacho, redespacho, real FROM elegidas WHERE rn = 1
  ON CONFLICT (planta_id, fecha) DO UPDATE SET programada_despacho_kwh = EXCLUDED.programada_despacho_kwh,
      programada_redespacho_kwh = EXCLUDED.programada_redespacho_kwh, real_estimada_kwh = EXCLUDED.real_estimada_kwh
    WHERE (energia.generacion_diaria_planta.programada_despacho_kwh, energia.generacion_diaria_planta.programada_redespacho_kwh,
           energia.generacion_diaria_planta.real_estimada_kwh)
          IS DISTINCT FROM (EXCLUDED.programada_despacho_kwh, EXCLUDED.programada_redespacho_kwh, EXCLUDED.real_estimada_kwh)
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM tmp_diaria) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;
