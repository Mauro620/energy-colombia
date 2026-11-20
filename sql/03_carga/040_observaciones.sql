-- Observaciones IDEAM acumuladas (D06) -> sensor, unidad_medida y observacion (todo lo acumulado en data/raw hasta hoy).
-- D08: -9998, -9999 y los centinelas propios de cada sensor NO se cargan como valor (DQ08); fuera del rango del sensor = cuarentena (DQ09).
-- Los rangos son PROVISIONALES (S-02): salen de min/max reales de una ventana de ~12 h y de limites fisicos; ver docs/decisiones/0002-modelo-e1.md.
BEGIN;
SET LOCAL work_mem = '128MB';
SELECT control.iniciar_lote('ideam_observaciones', 'energia.observacion') AS lote \gset
TRUNCATE staging.stg_observacion;
\copy staging.stg_observacion FROM '/stage/observacion.csv' WITH (FORMAT csv, HEADER true)

-- Catalogo de sensores: codigo, descripcion y unidad salen de la observacion; el sensor 0245 no trae descripcion ni unidad en el origen.
INSERT INTO energia.unidad_medida (simbolo)
  SELECT DISTINCT btrim(unidadmedida) FROM staging.stg_observacion WHERE nullif(btrim(unidadmedida), '') IS NOT NULL
  ON CONFLICT (simbolo) DO NOTHING;

-- Rango plausible y centinelas por sensor (S-02). Limites fisicos: humedad 0-100 %, temperatura -15 a 50 C (DQ09), viento 0-60 m/s,
-- direccion 0-360 grados, presion 500-1100 hPa. El resto, la envolvente real redondeada. 0245 sin descripcion: sin rango.
CREATE TEMP TABLE tmp_rango_sensor (codigo char(4), valor_min numeric, valor_max numeric, centinelas numeric[]) ON COMMIT DROP;
INSERT INTO tmp_rango_sensor VALUES
  ('0027',    0,  100, '{-9998,-9999}'),          -- humedad relativa del aire %
  ('0068',  -15,   50, '{-9998,-9999,995}'),      -- temperatura del aire C
  ('0069',  -15,   50, '{-9998,-9999,995}'),      -- temperatura maxima C
  ('0070',  -15,   50, '{-9998,-9999,995}'),      -- temperatura minima C
  ('0103',    0,   60, '{-9998,-9999,1000}'),     -- velocidad del viento m/s
  ('0104',    0,  360, '{-9998,-9999,999}'),      -- direccion del viento grados
  ('0230',  -10, 2700, '{-9998,-9999}'),          -- nivel horario cm (real -8.2 a 2669)
  ('0231',  -50,  150, '{-9998,-9999,-200}'),     -- nivel maximo horario cm
  ('0232',  -50,  150, '{-9998,-9999,200}'),      -- nivel minimo horario cm
  ('0240',    0,  100, '{-9998,-9999}'),          -- precipitacion 10 min mm
  ('0241',    0,   60, '{-9998,-9999}'),          -- temperatura del suelo 10 cm C
  ('0242',    0,   60, '{-9998,-9999}'),          -- temperatura del suelo 30 cm C
  ('0243',    0,   60, '{-9998,-9999}'),          -- temperatura del suelo 50 cm C
  ('0246',    0,  100, '{-9998,-9999}'),          -- humedad del suelo 30 cm %
  ('0247',    0,  100, '{-9998,-9999}'),          -- humedad del suelo 50 cm %
  ('0255',  500, 1100, '{-9998,-9999}'),          -- presion atmosferica hPa
  ('0260',    0,   20, '{-9998,-9999}');          -- evaporacion horaria mm

INSERT INTO energia.sensor (codigo, descripcion, unidad_id, valor_min, valor_max, centinelas)
SELECT s.codigo, s.descripcion, u.unidad_id, r.valor_min, r.valor_max, coalesce(r.centinelas, '{-9998,-9999}')
FROM (SELECT lpad(btrim(codigosensor), 4, '0') AS codigo, max(nullif(btrim(descripcionsensor), '')) AS descripcion, max(nullif(btrim(unidadmedida), '')) AS unidad
        FROM staging.stg_observacion WHERE btrim(codigosensor) ~ '^[0-9]{1,4}$' GROUP BY 1) s
LEFT JOIN energia.unidad_medida u ON u.simbolo = s.unidad
LEFT JOIN tmp_rango_sensor r ON r.codigo = s.codigo
ON CONFLICT (codigo) DO UPDATE SET descripcion = EXCLUDED.descripcion, unidad_id = EXCLUDED.unidad_id, valor_min = EXCLUDED.valor_min,
    valor_max = EXCLUDED.valor_max, centinelas = EXCLUDED.centinelas
  WHERE (energia.sensor.descripcion, energia.sensor.unidad_id, energia.sensor.valor_min, energia.sensor.valor_max, energia.sensor.centinelas)
        IS DISTINCT FROM (EXCLUDED.descripcion, EXCLUDED.unidad_id, EXCLUDED.valor_min, EXCLUDED.valor_max, EXCLUDED.centinelas);

CREATE TEMP TABLE tmp_obs ON COMMIT DROP AS
SELECT e.estacion_id, sn.sensor_id, v.valor, v.fecha, s.fila_origen, r.regla,
       CASE WHEN r.regla IS NOT NULL THEN to_jsonb(s) END AS registro
FROM staging.stg_observacion s
LEFT JOIN energia.estacion e ON e.codigo = lpad(btrim(s.codigoestacion), 10, '0')
LEFT JOIN energia.sensor sn ON sn.codigo = lpad(btrim(s.codigosensor), 4, '0')
CROSS JOIN LATERAL (SELECT control.a_numero(s.valorobservado) AS valor,
                           CASE WHEN s.fechaobservacion ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$'
                                THEN (s.fechaobservacion::timestamp AT TIME ZONE 'America/Bogota') END AS fecha) v
CROSS JOIN LATERAL (SELECT CASE
    WHEN btrim(s.codigoestacion) !~ '^[0-9]{1,10}$' OR btrim(s.codigosensor) !~ '^[0-9]{1,4}$' THEN 'RN05'
    WHEN v.valor IS NULL OR v.fecha IS NULL THEN 'RN18'
    WHEN e.estacion_id IS NULL THEN 'DQ15'
    WHEN sn.sensor_id IS NULL THEN 'RN17'
    WHEN v.valor = ANY (sn.centinelas) THEN 'DQ08'
    WHEN sn.valor_min IS NOT NULL AND v.valor NOT BETWEEN sn.valor_min AND sn.valor_max THEN 'DQ09'
  END AS regla) r;

WITH rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla,
         CASE regla WHEN 'DQ08' THEN 'centinela de dato faltante (no se carga como valor)' WHEN 'DQ09' THEN 'valor fuera del rango plausible del sensor'
                    WHEN 'DQ15' THEN 'estacion que no existe en el catalogo cargado (sin cruce DIVIPOLA o inexistente)' ELSE 'observacion invalida' END,
         registro
  FROM tmp_obs WHERE regla IS NOT NULL RETURNING 1),
elegidas AS (
  SELECT DISTINCT ON (estacion_id, sensor_id, fecha) estacion_id, sensor_id, fecha, valor FROM tmp_obs WHERE regla IS NULL
  ORDER BY estacion_id, sensor_id, fecha, fila_origen DESC),
up AS (
  INSERT INTO energia.observacion (estacion_id, sensor_id, fecha_observacion, valor)
  SELECT estacion_id, sensor_id, fecha, valor FROM elegidas
  ON CONFLICT (estacion_id, sensor_id, fecha_observacion) DO UPDATE SET valor = EXCLUDED.valor
    WHERE energia.observacion.valor IS DISTINCT FROM EXCLUDED.valor
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM tmp_obs) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;
