-- Catalogo IDEAM completo (57 706 filas = 9 935 estaciones) -> catalogos + estacion.
-- Codigo: el catalogo trae el mismo codigo con 8 y con 10 digitos; se normaliza con lpad a 10 (S-06). Duplicados: queda la fila de
-- 10 digitos de menor posicion. Geografia por nombre normalizado contra DIVIPOLA (D05); sin cruce = cuarentena DQ14.
BEGIN;
SELECT control.iniciar_lote('socrata_hp9r-jxuu', 'energia.estacion') AS lote \gset
TRUNCATE staging.stg_estacion;
\copy staging.stg_estacion FROM '/stage/estacion.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE tmp_est ON COMMIT DROP AS
SELECT lpad(btrim(s.codigo), 10, '0') AS codigo, length(btrim(s.codigo)) AS largo_origen, btrim(s.nombre) AS nombre, btrim(s.categoria) AS categoria,
       btrim(s.tecnologia) AS tecnologia, upper(btrim(s.estado)) AS estado, m.codigo AS municipio_codigo, btrim(s.entidad) AS entidad,
       btrim(s.area_hidrografica) AS area_hidrografica, btrim(s.zona_hidrografica) AS zona_hidrografica,
       nullif(btrim(s.subzona_hidrografica), '') AS subzona, nullif(btrim(s.corriente), '') AS corriente, nullif(btrim(s.area_operativa), '') AS area_operativa,
       v.latitud, v.longitud, v.altitud, v.instalacion, v.suspension, s.fila_origen, r.regla, to_jsonb(s) AS registro
FROM staging.stg_estacion s
LEFT JOIN energia.departamento d ON d.nombre_normalizado = energia.normalizar_texto(s.departamento)
LEFT JOIN energia.municipio m ON m.departamento_codigo = d.codigo AND m.nombre_normalizado = energia.normalizar_texto(s.municipio)
CROSS JOIN LATERAL (SELECT control.a_numero(s.latitud) AS latitud, control.a_numero(s.longitud) AS longitud, control.a_numero(s.altitud) AS altitud,
                           control.a_fecha(s.fecha_instalacion, 'DD/MM/YYYY') AS instalacion, control.a_fecha(s.fecha_suspension, 'DD/MM/YYYY') AS suspension) v
CROSS JOIN LATERAL (SELECT CASE
    WHEN btrim(s.codigo) !~ '^[0-9]{1,10}$' THEN 'RN05'
    WHEN upper(btrim(s.estado)) NOT IN ('ACTIVA', 'SUSPENDIDA', 'EN MANTENIMIENTO') THEN 'RN15'
    WHEN v.latitud IS NULL OR v.longitud IS NULL OR coalesce(btrim(s.nombre), '') = '' OR coalesce(btrim(s.categoria), '') = ''
         OR coalesce(btrim(s.tecnologia), '') = '' OR coalesce(btrim(s.entidad), '') = ''
         OR (s.fecha_instalacion IS NOT NULL AND v.instalacion IS NULL) OR (s.fecha_suspension IS NOT NULL AND v.suspension IS NULL)
         OR (s.altitud IS NOT NULL AND v.altitud IS NULL) THEN 'RN18'
    WHEN v.latitud NOT BETWEEN -5 AND 16 OR v.longitud NOT BETWEEN -84 AND -66 OR v.altitud NOT BETWEEN 0 AND 6000 THEN 'RN07'
    WHEN v.instalacion IS NOT NULL AND v.suspension IS NOT NULL AND v.suspension < v.instalacion THEN 'RN12'
    WHEN m.codigo IS NULL THEN 'DQ14'
  END AS regla) r;

CREATE TEMP TABLE tmp_est_elegida ON COMMIT DROP AS
SELECT * FROM (SELECT t.*, row_number() OVER (PARTITION BY codigo ORDER BY (largo_origen = 10) DESC, fila_origen) AS rn
               FROM tmp_est t WHERE regla IS NULL) x WHERE rn = 1;

INSERT INTO energia.categoria_estacion (nombre) SELECT DISTINCT categoria FROM tmp_est_elegida ON CONFLICT (nombre) DO NOTHING;
INSERT INTO energia.tecnologia_estacion (nombre) SELECT DISTINCT tecnologia FROM tmp_est_elegida ON CONFLICT (nombre) DO NOTHING;
INSERT INTO energia.entidad (nombre) SELECT DISTINCT entidad FROM tmp_est_elegida ON CONFLICT (nombre) DO NOTHING;
INSERT INTO energia.zona_hidrografica (area_hidrografica, nombre)
  SELECT DISTINCT area_hidrografica, zona_hidrografica FROM tmp_est_elegida WHERE area_hidrografica IS NOT NULL AND zona_hidrografica IS NOT NULL
  ON CONFLICT (area_hidrografica, nombre) DO NOTHING;

WITH rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla, CASE regla WHEN 'DQ14' THEN 'departamento y municipio no cruzan con DIVIPOLA por nombre normalizado' ELSE 'estacion invalida' END, registro
  FROM tmp_est WHERE regla IS NOT NULL RETURNING 1),
up AS (
  INSERT INTO energia.estacion (codigo, nombre, categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, zona_hidrografica_id,
                                subzona_hidrografica, corriente, area_operativa, latitud, longitud, altitud, fecha_instalacion, fecha_suspension)
  SELECT e.codigo, e.nombre, c.categoria_id, t.tecnologia_estacion_id, e.estado::energia.estado_estacion, e.municipio_codigo, en.entidad_id, z.zona_hidrografica_id,
         e.subzona, e.corriente, e.area_operativa, e.latitud, e.longitud, e.altitud::int, e.instalacion, e.suspension
  FROM tmp_est_elegida e
  JOIN energia.categoria_estacion c ON c.nombre = e.categoria
  JOIN energia.tecnologia_estacion t ON t.nombre = e.tecnologia
  JOIN energia.entidad en ON en.nombre = e.entidad
  LEFT JOIN energia.zona_hidrografica z ON z.area_hidrografica = e.area_hidrografica AND z.nombre = e.zona_hidrografica
  ON CONFLICT (codigo) DO UPDATE SET nombre = EXCLUDED.nombre, categoria_id = EXCLUDED.categoria_id, tecnologia_estacion_id = EXCLUDED.tecnologia_estacion_id,
      estado = EXCLUDED.estado, municipio_codigo = EXCLUDED.municipio_codigo, entidad_id = EXCLUDED.entidad_id,
      zona_hidrografica_id = EXCLUDED.zona_hidrografica_id, subzona_hidrografica = EXCLUDED.subzona_hidrografica, corriente = EXCLUDED.corriente,
      area_operativa = EXCLUDED.area_operativa, latitud = EXCLUDED.latitud, longitud = EXCLUDED.longitud, altitud = EXCLUDED.altitud,
      fecha_instalacion = EXCLUDED.fecha_instalacion, fecha_suspension = EXCLUDED.fecha_suspension
    WHERE (energia.estacion.nombre, energia.estacion.categoria_id, energia.estacion.tecnologia_estacion_id, energia.estacion.estado, energia.estacion.municipio_codigo,
           energia.estacion.entidad_id, energia.estacion.zona_hidrografica_id, energia.estacion.subzona_hidrografica, energia.estacion.corriente,
           energia.estacion.area_operativa, energia.estacion.latitud, energia.estacion.longitud, energia.estacion.altitud,
           energia.estacion.fecha_instalacion, energia.estacion.fecha_suspension)
          IS DISTINCT FROM (EXCLUDED.nombre, EXCLUDED.categoria_id, EXCLUDED.tecnologia_estacion_id, EXCLUDED.estado, EXCLUDED.municipio_codigo,
           EXCLUDED.entidad_id, EXCLUDED.zona_hidrografica_id, EXCLUDED.subzona_hidrografica, EXCLUDED.corriente, EXCLUDED.area_operativa,
           EXCLUDED.latitud, EXCLUDED.longitud, EXCLUDED.altitud, EXCLUDED.fecha_instalacion, EXCLUDED.fecha_suspension)
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM tmp_est) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;
