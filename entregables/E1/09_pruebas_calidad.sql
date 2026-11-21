-- Pruebas de calidad de los datos cargados.
-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d <base> -f 09_pruebas_calidad.sql

-- ======================================================================
-- sql/05_pruebas/052_pruebas_calidad.sql
-- ======================================================================
-- Pruebas de calidad de la carga. PASS/FAIL con RAISE NOTICE; las dos ultimas solo reportan (no fallan).
\set ON_ERROR_STOP on
\pset null '(nulo)'

\echo '=== Q1 Conteos por lote: leidas = insertadas + actualizadas + omitidas + rechazadas, y leidas = filas en staging'
WITH staging AS (
  SELECT 'divipola_vcjz-niiq' AS fuente, count(*) AS n FROM staging.stg_divipola_dpto UNION ALL
  SELECT 'divipola_gdxc-w37w', count(*) FROM staging.stg_divipola_mpio UNION ALL SELECT 'xm_ListadoAgentes', count(*) FROM staging.stg_agente UNION ALL
  SELECT 'xm_ListadoRecursos', count(*) FROM staging.stg_listado_recursos UNION ALL SELECT 'socrata_tq63-itzr', count(*) FROM staging.stg_upme UNION ALL
  SELECT 'xm_CapEfecNeta', count(*) FROM staging.stg_capacidad UNION ALL SELECT 'simem_E17D25', count(*) FROM staging.stg_gen_diaria UNION ALL
  SELECT 'simem_055A4D', count(*) FROM staging.stg_gen_horaria UNION ALL SELECT 'socrata_hp9r-jxuu', count(*) FROM staging.stg_estacion UNION ALL
  SELECT 'ideam_observaciones', count(*) FROM staging.stg_observacion),
ultimo AS (SELECT DISTINCT ON (fuente) * FROM control.carga_lote WHERE estado = 'ok' ORDER BY fuente, lote_id DESC)
SELECT l.lote_id, l.fuente, l.filas_leidas AS leidas, l.filas_insertadas AS ins, l.filas_actualizadas AS act, l.filas_omitidas AS omit, l.filas_rechazadas AS rech,
       s.n AS staging,
       CASE WHEN l.filas_leidas = l.filas_insertadas + l.filas_actualizadas + l.filas_omitidas + l.filas_rechazadas AND l.filas_leidas = s.n THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM ultimo l JOIN staging s USING (fuente) ORDER BY l.lote_id;

\echo '=== Q2 Rechazos por regla en el ultimo lote de cada fuente'
SELECT l.fuente, r.regla, count(*) AS filas, min(r.motivo) AS motivo
FROM control.registro_rechazado r JOIN control.carga_lote l USING (lote_id)
WHERE l.lote_id IN (SELECT max(lote_id) FROM control.carga_lote WHERE estado = 'ok' GROUP BY fuente)
GROUP BY l.fuente, r.regla ORDER BY l.fuente, filas DESC;

\echo '=== Q3 Duplicados por clave de negocio y huerfanas (deben ser 0)'
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT * FROM (VALUES
    ('planta: codigo repetido', 'SELECT count(*) FROM (SELECT codigo FROM energia.planta GROUP BY codigo HAVING count(*) > 1) x'),
    ('estacion: codigo repetido', 'SELECT count(*) FROM (SELECT codigo FROM energia.estacion GROUP BY codigo HAVING count(*) > 1) x'),
    ('agente: codigo repetido', 'SELECT count(*) FROM (SELECT codigo_sic FROM energia.agente GROUP BY 1 HAVING count(*) > 1) x'),
    ('generacion diaria: (planta, fecha) repetida', 'SELECT count(*) FROM (SELECT 1 FROM energia.generacion_diaria_planta GROUP BY planta_id, fecha HAVING count(*) > 1) x'),
    ('generacion horaria: (planta, hora) repetida', 'SELECT count(*) FROM (SELECT 1 FROM energia.generacion_horaria_planta GROUP BY planta_id, fecha_hora HAVING count(*) > 1) x'),
    ('observacion: (estacion, sensor, instante) repetida', 'SELECT count(*) FROM (SELECT 1 FROM energia.observacion GROUP BY estacion_id, sensor_id, fecha_observacion HAVING count(*) > 1) x'),
    ('UPME: (periodo, fuente) repetida', 'SELECT count(*) FROM (SELECT 1 FROM energia.generacion_mensual_upme GROUP BY periodo, fuente_energetica_id HAVING count(*) > 1) x'),
    ('huerfanas: observacion sin estacion', 'SELECT count(*) FROM energia.observacion o WHERE NOT EXISTS (SELECT 1 FROM energia.estacion e WHERE e.estacion_id = o.estacion_id)'),
    ('huerfanas: generacion horaria sin planta', 'SELECT count(*) FROM energia.generacion_horaria_planta g WHERE NOT EXISTS (SELECT 1 FROM energia.planta p WHERE p.planta_id = g.planta_id)'),
    ('huerfanas: capacidad sin planta', 'SELECT count(*) FROM energia.capacidad_planta c WHERE NOT EXISTS (SELECT 1 FROM energia.planta p WHERE p.planta_id = c.planta_id)'),
    ('huerfanas: estacion sin municipio', 'SELECT count(*) FROM energia.estacion e WHERE NOT EXISTS (SELECT 1 FROM energia.municipio m WHERE m.codigo = e.municipio_codigo)'),
    ('vigencias de capacidad solapadas', 'SELECT count(*) FROM energia.capacidad_planta a JOIN energia.capacidad_planta b ON a.planta_id = b.planta_id AND a.capacidad_id < b.capacidad_id AND a.vigencia && b.vigencia')
  ) v(nombre, consulta)
  LOOP
    DECLARE n bigint;
    BEGIN
      EXECUTE c.consulta INTO n;
      RAISE NOTICE '% | esperado 0 obtenido % -> %', c.nombre, n, CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END;
    END;
  END LOOP;
END $$;

\echo '=== Q4 (reporte) Cruce DIVIPOLA de las estaciones del catalogo y su efecto en las observaciones (S-07)'
WITH est AS (SELECT DISTINCT ON (lpad(btrim(codigo), 10, '0')) lpad(btrim(codigo), 10, '0') AS codigo, departamento, municipio FROM staging.stg_estacion ORDER BY 1, fila_origen),
cruce AS (
  SELECT e.codigo, (m.codigo IS NOT NULL) AS cruza FROM est e
  LEFT JOIN energia.departamento d ON d.nombre_normalizado = energia.normalizar_texto(e.departamento)
  LEFT JOIN energia.municipio m ON m.departamento_codigo = d.codigo AND m.nombre_normalizado = energia.normalizar_texto(e.municipio))
SELECT count(*) AS estaciones, count(*) FILTER (WHERE cruza) AS con_cruce, round(100.0 * count(*) FILTER (WHERE cruza) / count(*), 1) AS cruce_pct,
       (SELECT count(*) FROM energia.estacion) AS estaciones_cargadas FROM cruce;
SELECT count(*) AS observaciones_en_staging, count(*) FILTER (WHERE r.regla = 'DQ15') AS rechazadas_por_estacion_sin_cruce,
       round(100.0 * count(*) FILTER (WHERE r.regla = 'DQ15') / count(*), 1) AS pct_perdido
FROM staging.stg_observacion s
LEFT JOIN control.registro_rechazado r ON r.regla = 'DQ15' AND r.registro->>'fila_origen' = s.fila_origen::text
  AND r.lote_id = (SELECT max(lote_id) FROM control.carga_lote WHERE fuente = 'ideam_observaciones' AND estado = 'ok');

\echo '=== Q5 (reporte) Total diario E17D25 vs suma horaria de 055A4D, por mes (dias en los dos periodos; kWh)'
WITH h AS (SELECT (fecha_hora AT TIME ZONE 'America/Bogota')::date AS fecha, sum(energia_kwh) AS horaria_kwh FROM energia.generacion_horaria_planta GROUP BY 1),
d AS (SELECT fecha, sum(real_estimada_kwh) AS diaria_kwh FROM energia.generacion_diaria_planta GROUP BY 1)
SELECT date_trunc('month', h.fecha)::date AS mes, count(*) AS dias, round(sum(d.diaria_kwh) / 1e6, 1) AS diaria_gwh, round(sum(h.horaria_kwh) / 1e6, 1) AS horaria_gwh,
       round(100 * (sum(h.horaria_kwh) - sum(d.diaria_kwh)) / sum(d.diaria_kwh), 2) AS diferencia_pct
FROM h JOIN d USING (fecha) GROUP BY 1 ORDER BY 1;
