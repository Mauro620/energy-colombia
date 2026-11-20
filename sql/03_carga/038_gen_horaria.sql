-- SIMEM 055A4D -> generacion_horaria_planta (D02-rev b). El origen trae hasta 6 versiones por (planta, hora): se guarda UNA, la de mayor
-- orden en energia.version_liquidacion (S-01). FechaHora viene en hora Colombia sin zona: se interpreta America/Bogota y se guarda en UTC (D11).
-- Conteos: leidas = filas de staging; omitidas = versiones inferiores o repetidas; rechazadas = reglas RN05/RN17/RN04/RN18/RN01 y RN10.
BEGIN;
SET LOCAL work_mem = '256MB';
SELECT control.iniciar_lote('simem_055A4D', 'energia.generacion_horaria_planta') AS lote \gset
TRUNCATE staging.stg_gen_horaria;
\copy staging.stg_gen_horaria FROM '/stage/gen_horaria.csv' WITH (FORMAT csv, HEADER true)

-- 1) Clasifica cada fila de staging. El registro jsonb solo se guarda para las que se rechazan.
CREATE TEMP TABLE tmp_h ON COMMIT DROP AS
SELECT p.planta_id, v.orden, s.version AS version_codigo, s.fila_origen, r.regla,
       CASE WHEN r.regla IS NULL THEN (s.fechahora::timestamp AT TIME ZONE 'America/Bogota') END AS fecha_hora,
       CASE WHEN r.regla IS NULL THEN control.a_numero(s.valor) END AS energia,
       CASE WHEN r.regla IS NOT NULL THEN to_jsonb(s) END AS registro
FROM staging.stg_gen_horaria s
LEFT JOIN energia.planta p ON p.codigo = upper(btrim(s.codigoplanta))
LEFT JOIN energia.version_liquidacion v ON v.codigo = s.version
CROSS JOIN LATERAL (SELECT CASE
    WHEN upper(btrim(s.codigoplanta)) !~ '^[A-Z0-9]{4}$' THEN 'RN05'
    WHEN s.fechahora !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' OR control.a_numero(s.valor) IS NULL THEN 'RN18'
    WHEN s.fechahora !~ ' [0-9]{2}:00:00$' THEN 'RN04'
    WHEN control.a_numero(s.valor) < 0 THEN 'RN01'
    WHEN p.planta_id IS NULL OR v.codigo IS NULL THEN 'RN17'
  END AS regla) r;

-- 2) De las validas, una por (planta, hora): la version de mayor orden.
CREATE TEMP TABLE tmp_h_elegida ON COMMIT DROP AS
SELECT DISTINCT ON (planta_id, fecha_hora) planta_id, fecha_hora, energia, version_codigo, orden
FROM tmp_h WHERE regla IS NULL
ORDER BY planta_id, fecha_hora, orden DESC, fila_origen DESC;

-- 3) RN10: la energia no supera la capacidad vigente x 1.10 (solo si hay capacidad vigente ese dia, hora Colombia).
CREATE TEMP TABLE tmp_h_exceso ON COMMIT DROP AS
SELECT e.planta_id, e.fecha_hora, e.energia, e.version_codigo, c.capacidad_kw
FROM tmp_h_elegida e
JOIN energia.capacidad_planta c ON c.planta_id = e.planta_id AND c.vigencia @> (e.fecha_hora AT TIME ZONE 'America/Bogota')::date
WHERE e.energia > c.capacidad_kw * 1.10;

WITH rej_formato AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla, CASE regla WHEN 'RN17' THEN 'planta que no esta en el listado de recursos' ELSE 'fila de generacion horaria invalida' END, registro
  FROM tmp_h WHERE regla IS NOT NULL RETURNING 1),
rej_capacidad AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, 'RN10', format('%s kWh superan la capacidad vigente %s kW x 1.10', energia, capacidad_kw),
         jsonb_build_object('planta_id', planta_id, 'fecha_hora', fecha_hora, 'energia_kwh', energia, 'version', version_codigo, 'capacidad_kw', capacidad_kw)
  FROM tmp_h_exceso RETURNING 1),
up AS (
  INSERT INTO energia.generacion_horaria_planta (planta_id, fecha_hora, energia_kwh, version_codigo)
  SELECT e.planta_id, e.fecha_hora, e.energia, e.version_codigo
  FROM tmp_h_elegida e
  WHERE NOT EXISTS (SELECT 1 FROM tmp_h_exceso x WHERE x.planta_id = e.planta_id AND x.fecha_hora = e.fecha_hora)
  ON CONFLICT (planta_id, fecha_hora) DO UPDATE SET energia_kwh = EXCLUDED.energia_kwh, version_codigo = EXCLUDED.version_codigo
    WHERE (SELECT orden FROM energia.version_liquidacion WHERE codigo = EXCLUDED.version_codigo)
          >= (SELECT orden FROM energia.version_liquidacion WHERE codigo = energia.generacion_horaria_planta.version_codigo)
      AND (energia.generacion_horaria_planta.energia_kwh, energia.generacion_horaria_planta.version_codigo)
          IS DISTINCT FROM (EXCLUDED.energia_kwh, EXCLUDED.version_codigo)
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM tmp_h) AS leidas, (SELECT count(*) FROM rej_formato) + (SELECT count(*) FROM rej_capacidad) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;
