-- Vistas del esquema analitica. Idempotente (CREATE OR REPLACE). Cada vista lleva un bloque con la pregunta que responde.
\pset null '(nulo)'

/* ---------------------------------------------------------------------
   V1  v_participacion_mensual_upme
   Pregunta: que porcentaje de la generacion mensual de UPME aporta cada fuente?
   Como: para cada fila (mes, fuente) divide su GWh entre la suma de todas las fuentes del mismo mes.
         SUM() OVER (PARTITION BY periodo) calcula ese total sin agrupar. El porcentaje no se guarda: se calcula aqui (D09, H12).
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analitica.v_participacion_mensual_upme AS
SELECT g.periodo, f.nombre AS fuente, g.generacion_total_gwh, g.parcial,
       round(100 * g.generacion_total_gwh / nullif(sum(g.generacion_total_gwh) OVER (PARTITION BY g.periodo), 0), 6) AS participacion_pct
FROM energia.generacion_mensual_upme g
JOIN energia.fuente_energetica f USING (fuente_energetica_id);

/* ---------------------------------------------------------------------
   V2  v_generacion_diaria_tecnologia
   Pregunta: cuanta energia programada y real genero cada tecnologia por dia? (fuente E17D25, en kWh)
   Como: une cada generacion diaria con su planta y su tecnologia y suma por (fecha, tecnologia).
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analitica.v_generacion_diaria_tecnologia AS
SELECT d.fecha, t.nombre AS tecnologia, count(*) AS plantas,
       sum(d.programada_despacho_kwh) AS programada_despacho_kwh, sum(d.programada_redespacho_kwh) AS programada_redespacho_kwh,
       sum(d.real_estimada_kwh) AS real_estimada_kwh
FROM energia.generacion_diaria_planta d
JOIN energia.planta p USING (planta_id)
JOIN energia.tecnologia t USING (tecnologia_id)
GROUP BY d.fecha, t.nombre;

/* ---------------------------------------------------------------------
   V3  v_desviacion_programado_real
   Pregunta: cuanto se desvio cada planta de lo programado (redespacho) en cada mes?
   Como: suma por planta y mes lo programado y lo real. Desviacion = real - programada; el porcentaje es esa
         diferencia sobre lo programado (nullif evita dividir entre cero).
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analitica.v_desviacion_programado_real AS
SELECT p.codigo AS planta, p.nombre, t.nombre AS tecnologia, date_trunc('month', d.fecha)::date AS mes,
       sum(d.programada_redespacho_kwh) AS programada_kwh, sum(d.real_estimada_kwh) AS real_kwh,
       sum(d.real_estimada_kwh - d.programada_redespacho_kwh) AS desviacion_kwh,
       round(100 * sum(d.real_estimada_kwh - d.programada_redespacho_kwh) / nullif(sum(d.programada_redespacho_kwh), 0), 2) AS desviacion_pct
FROM energia.generacion_diaria_planta d
JOIN energia.planta p USING (planta_id)
JOIN energia.tecnologia t USING (tecnologia_id)
GROUP BY p.codigo, p.nombre, t.nombre, date_trunc('month', d.fecha);

/* ---------------------------------------------------------------------
   V4  v_conciliacion_xm_upme
   Pregunta: XM y UPME reportan la misma generacion? Comparacion por mes y fuente energetica (no se suman, H13).
   Como: 1) CTE xm: real estimada diaria de XM sumada por mes y fuente, de kWh a GWh (/1e6).
         2) La une con UPME (ya en GWh) por mes y fuente; solo salen los meses que tienen los dos.
         3) Calcula la diferencia en GWh y en porcentaje sobre UPME. Para ver que meses solo tiene uno: consulta Q10.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analitica.v_conciliacion_xm_upme AS
WITH xm AS (
  SELECT date_trunc('month', d.fecha)::date AS periodo, p.fuente_energetica_id, sum(d.real_estimada_kwh) / 1e6 AS xm_gwh
  FROM energia.generacion_diaria_planta d
  JOIN energia.planta p USING (planta_id)
  GROUP BY 1, 2)
SELECT x.periodo, f.nombre AS fuente, round(x.xm_gwh, 3) AS xm_gwh, u.generacion_total_gwh AS upme_gwh,
       round(x.xm_gwh - u.generacion_total_gwh, 3) AS diferencia_gwh,
       round(100 * (x.xm_gwh - u.generacion_total_gwh) / nullif(u.generacion_total_gwh, 0), 2) AS diferencia_pct,
       u.parcial AS upme_parcial
FROM xm x
JOIN energia.generacion_mensual_upme u ON u.periodo = x.periodo AND u.fuente_energetica_id = x.fuente_energetica_id
JOIN energia.fuente_energetica f ON f.fuente_energetica_id = x.fuente_energetica_id;

/* ---------------------------------------------------------------------
   V5  v_clima_diario_departamento
   Pregunta: que clima hubo cada dia en cada departamento, por sensor?
   Como: sigue la cadena observacion -> estacion -> municipio -> departamento y agrupa por dia (hora de Colombia),
         departamento y sensor. Los centinelas y valores fuera de rango no estan: la carga ya los aparto (D08).
   --------------------------------------------------------------------- */
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

-- Muestra de dos vistas
\echo 'V1 participacion UPME, ultimo mes (parcial)'
SELECT * FROM analitica.v_participacion_mensual_upme
WHERE periodo = (SELECT max(periodo) FROM energia.generacion_mensual_upme)
ORDER BY participacion_pct DESC LIMIT 5;

\echo 'V4 conciliacion XM vs UPME, julio de 2026'
SELECT * FROM analitica.v_conciliacion_xm_upme WHERE periodo = '2026-07-01' ORDER BY upme_gwh DESC;
