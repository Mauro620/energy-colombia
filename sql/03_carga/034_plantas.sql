-- ListadoRecursos (XM) -> catalogos y planta. Textos de XM a MAYUSCULAS ('Solar' = 'SOLAR').
-- 3 codigos repetidos (2 con filas identicas; PRG1 con dos nombres): queda la ULTIMA fila del listado (S-04).
BEGIN;
SELECT control.iniciar_lote('xm_ListadoRecursos', 'energia.planta') AS lote \gset
TRUNCATE staging.stg_listado_recursos;
\copy staging.stg_listado_recursos FROM '/stage/listado_recursos.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE tmp_listado ON COMMIT DROP AS
SELECT upper(btrim(code)) AS codigo, upper(btrim(name)) AS nombre, upper(btrim(type)) AS tecnologia, upper(btrim(disp)) AS tipo_despacho,
       upper(btrim(rectype)) AS clasificacion, upper(btrim(companycode)) AS agente, upper(btrim(enersource)) AS fuente,
       control.a_fecha(operstartdate) AS inicio, upper(btrim(state)) AS estado, fila_origen,
       CASE
         WHEN upper(btrim(code)) !~ '^[A-Z0-9]{4}$' THEN 'RN05'
         WHEN upper(btrim(state)) NOT IN ('OPERACION', 'PRUEBAS') OR upper(btrim(disp)) NOT IN ('DESPACHADO CENTRALMENTE', 'NO DESPACHADO CENTRALMENTE') THEN 'RN15'
         WHEN control.a_fecha(operstartdate) IS NULL OR coalesce(btrim(name), '') = '' OR coalesce(btrim(type), '') = ''
              OR coalesce(btrim(rectype), '') = '' OR coalesce(btrim(enersource), '') = '' THEN 'RN18'
         WHEN NOT EXISTS (SELECT 1 FROM energia.agente a WHERE a.codigo_sic = upper(btrim(s.companycode))) THEN 'RN17'
       END AS regla,
       to_jsonb(s) AS registro
FROM staging.stg_listado_recursos s;

-- Catalogos (dimensiones pequenas): se alimentan de las filas validas.
INSERT INTO energia.tecnologia (nombre) SELECT DISTINCT tecnologia FROM tmp_listado WHERE regla IS NULL ON CONFLICT (nombre) DO NOTHING;
INSERT INTO energia.clasificacion_recurso (nombre) SELECT DISTINCT clasificacion FROM tmp_listado WHERE regla IS NULL ON CONFLICT (nombre) DO NOTHING;
INSERT INTO energia.fuente_energetica (nombre, en_xm) SELECT DISTINCT fuente, true FROM tmp_listado WHERE regla IS NULL
  ON CONFLICT (nombre) DO UPDATE SET en_xm = true WHERE NOT energia.fuente_energetica.en_xm;

WITH rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla, 'recurso invalido en ListadoRecursos', registro FROM tmp_listado WHERE regla IS NOT NULL RETURNING 1),
elegidas AS (
  SELECT t.*, row_number() OVER (PARTITION BY codigo ORDER BY fila_origen DESC) AS rn FROM tmp_listado t WHERE regla IS NULL),
up AS (
  INSERT INTO energia.planta (codigo, nombre, tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion)
  SELECT e.codigo, e.nombre, t.tecnologia_id, f.fuente_energetica_id, c.clasificacion_id, e.tipo_despacho::energia.tipo_despacho,
         e.agente, e.estado::energia.estado_planta, e.inicio
  FROM elegidas e
  JOIN energia.tecnologia t ON t.nombre = e.tecnologia
  JOIN energia.fuente_energetica f ON f.nombre = e.fuente
  JOIN energia.clasificacion_recurso c ON c.nombre = e.clasificacion
  WHERE e.rn = 1
  ON CONFLICT (codigo) DO UPDATE SET nombre = EXCLUDED.nombre, tecnologia_id = EXCLUDED.tecnologia_id,
      fuente_energetica_id = EXCLUDED.fuente_energetica_id, clasificacion_id = EXCLUDED.clasificacion_id, tipo_despacho = EXCLUDED.tipo_despacho,
      agente_codigo = EXCLUDED.agente_codigo, estado = EXCLUDED.estado, fecha_inicio_operacion = EXCLUDED.fecha_inicio_operacion
    WHERE (energia.planta.nombre, energia.planta.tecnologia_id, energia.planta.fuente_energetica_id, energia.planta.clasificacion_id,
           energia.planta.tipo_despacho, energia.planta.agente_codigo, energia.planta.estado, energia.planta.fecha_inicio_operacion)
          IS DISTINCT FROM (EXCLUDED.nombre, EXCLUDED.tecnologia_id, EXCLUDED.fuente_energetica_id, EXCLUDED.clasificacion_id,
                            EXCLUDED.tipo_despacho, EXCLUDED.agente_codigo, EXCLUDED.estado, EXCLUDED.fecha_inicio_operacion)
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM tmp_listado) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;
