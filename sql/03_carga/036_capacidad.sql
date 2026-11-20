-- CapEfecNeta diaria (kW) -> capacidad_planta por periodos de vigencia (D13): dias consecutivos con el mismo valor forman un rango.
-- Los conteos del lote son DIAS de staging: insertadas = dias cubiertos por rangos nuevos; omitidas = dias ya cubiertos o repetidos.
BEGIN;
SELECT control.iniciar_lote('xm_CapEfecNeta', 'energia.capacidad_planta') AS lote \gset
TRUNCATE staging.stg_capacidad;
\copy staging.stg_capacidad FROM '/stage/capacidad.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE tmp_cap ON COMMIT DROP AS
SELECT p.planta_id, control.a_fecha(s.fecha) AS fecha, control.a_numero(s.valor) AS kw, s.fila_origen,
       CASE
         WHEN upper(btrim(s.codigo)) !~ '^[A-Z0-9]{4}$' THEN 'RN05'
         WHEN control.a_fecha(s.fecha) IS NULL OR control.a_numero(s.valor) IS NULL THEN 'RN18'
         WHEN control.a_numero(s.valor) <= 0 THEN 'RN02'
         WHEN p.planta_id IS NULL THEN 'RN17'
       END AS regla,
       to_jsonb(s) AS registro
FROM staging.stg_capacidad s LEFT JOIN energia.planta p ON p.codigo = upper(btrim(s.codigo));

WITH rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla, CASE regla WHEN 'RN17' THEN 'recurso con capacidad que no esta en el listado de recursos' ELSE 'capacidad invalida' END, registro
  FROM tmp_cap WHERE regla IS NOT NULL RETURNING 1),
dias AS (  -- un valor por (planta, dia): si se repite queda el ultimo
  SELECT DISTINCT ON (planta_id, fecha) planta_id, fecha, kw FROM tmp_cap WHERE regla IS NULL ORDER BY planta_id, fecha, fila_origen DESC),
islas AS (  -- dias consecutivos con el mismo valor comparten (fecha - n)
  SELECT planta_id, kw, fecha - (row_number() OVER (PARTITION BY planta_id, kw ORDER BY fecha))::int AS grupo, fecha FROM dias),
rangos AS (
  SELECT planta_id, kw, daterange(min(fecha), max(fecha) + 1, '[)') AS vigencia FROM islas GROUP BY planta_id, kw, grupo),
ins AS (
  INSERT INTO energia.capacidad_planta (planta_id, vigencia, capacidad_kw)
  SELECT planta_id, vigencia, kw FROM rangos ORDER BY planta_id, lower(vigencia)
  ON CONFLICT DO NOTHING  -- cubre el EXCLUDE: un rango ya cargado o solapado se omite
  RETURNING (upper(vigencia) - lower(vigencia)) AS dias)
SELECT (SELECT count(*) FROM tmp_cap) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT coalesce(sum(dias), 0) FROM ins) AS ins, (SELECT count(*) FROM ins) AS rangos \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, 0, :leidas - :ins - :rech, :rech, format('%s rangos nuevos', :rangos));
COMMIT;
