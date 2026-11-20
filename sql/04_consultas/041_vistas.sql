-- Vistas del esquema analitica. Cada una indica la pregunta de negocio que responde. Idempotente (CREATE OR REPLACE).

-- V1. Que porcentaje de la generacion mensual de UPME aporta cada fuente? (D09, H12: el porcentaje no se almacena, se calcula)
CREATE OR REPLACE VIEW analitica.v_participacion_mensual_upme AS
SELECT g.periodo, f.nombre AS fuente, g.generacion_total_gwh, g.parcial,
       round(100 * g.generacion_total_gwh / nullif(sum(g.generacion_total_gwh) OVER (PARTITION BY g.periodo), 0), 6) AS participacion_pct
FROM energia.generacion_mensual_upme g
JOIN energia.fuente_energetica f USING (fuente_energetica_id);

-- V2. Cuanta energia real y programada genero cada tecnologia por dia? (E17D25)
CREATE OR REPLACE VIEW analitica.v_generacion_diaria_tecnologia AS
SELECT d.fecha, t.nombre AS tecnologia, count(*) AS plantas,
       sum(d.programada_despacho_kwh) AS programada_despacho_kwh, sum(d.programada_redespacho_kwh) AS programada_redespacho_kwh,
       sum(d.real_estimada_kwh) AS real_estimada_kwh
FROM energia.generacion_diaria_planta d
JOIN energia.planta p USING (planta_id)
JOIN energia.tecnologia t USING (tecnologia_id)
GROUP BY d.fecha, t.nombre;

-- V3. Cuanto se desvio cada planta de lo programado (redespacho) en cada mes? Desviacion = real - programada.
CREATE OR REPLACE VIEW analitica.v_desviacion_programado_real AS
SELECT p.codigo AS planta, p.nombre, t.nombre AS tecnologia, date_trunc('month', d.fecha)::date AS mes,
       sum(d.programada_redespacho_kwh) AS programada_kwh, sum(d.real_estimada_kwh) AS real_kwh,
       sum(d.real_estimada_kwh - d.programada_redespacho_kwh) AS desviacion_kwh,
       round(100 * sum(d.real_estimada_kwh - d.programada_redespacho_kwh) / nullif(sum(d.programada_redespacho_kwh), 0), 2) AS desviacion_pct
FROM energia.generacion_diaria_planta d
JOIN energia.planta p USING (planta_id)
JOIN energia.tecnologia t USING (tecnologia_id)
GROUP BY p.codigo, p.nombre, t.nombre, date_trunc('month', d.fecha);

-- V4. XM y UPME cuentan la misma generacion? Conciliacion por mes y fuente energetica (H13: no se suman, se comparan).
-- XM = real estimada de las plantas del listado (kWh -> GWh); UPME en GWh. FULL JOIN: muestra tambien los meses que solo tiene uno.
CREATE OR REPLACE VIEW analitica.v_conciliacion_xm_upme AS
WITH xm AS (
  SELECT date_trunc('month', d.fecha)::date AS periodo, p.fuente_energetica_id, sum(d.real_estimada_kwh) / 1e6 AS xm_gwh
  FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id)
  GROUP BY 1, 2)
SELECT coalesce(x.periodo, u.periodo) AS periodo, f.nombre AS fuente, round(x.xm_gwh, 3) AS xm_gwh, u.generacion_total_gwh AS upme_gwh,
       round(x.xm_gwh - u.generacion_total_gwh, 3) AS diferencia_gwh,
       round(100 * (x.xm_gwh - u.generacion_total_gwh) / nullif(u.generacion_total_gwh, 0), 2) AS diferencia_pct, coalesce(u.parcial, false) AS upme_parcial
FROM xm x
FULL JOIN energia.generacion_mensual_upme u ON u.periodo = x.periodo AND u.fuente_energetica_id = x.fuente_energetica_id
JOIN energia.fuente_energetica f ON f.fuente_energetica_id = coalesce(x.fuente_energetica_id, u.fuente_energetica_id);

-- V5. Que clima hubo cada dia en cada departamento? Valores sin centinelas ni fuera de rango: la carga ya los aparto (D08).
CREATE OR REPLACE VIEW analitica.v_clima_diario_departamento AS
SELECT (o.fecha_observacion AT TIME ZONE 'America/Bogota')::date AS fecha, d.nombre AS departamento, s.codigo AS sensor,
       s.descripcion, u.simbolo AS unidad, count(*) AS lecturas, round(avg(o.valor), 3) AS promedio, min(o.valor) AS minimo, max(o.valor) AS maximo,
       sum(o.valor) AS suma
FROM energia.observacion o
JOIN energia.sensor s USING (sensor_id)
LEFT JOIN energia.unidad_medida u USING (unidad_id)
JOIN energia.estacion e USING (estacion_id)
JOIN energia.municipio m ON m.codigo = e.municipio_codigo
JOIN energia.departamento d ON d.codigo = m.departamento_codigo
GROUP BY 1, d.nombre, s.codigo, s.descripcion, u.simbolo;
