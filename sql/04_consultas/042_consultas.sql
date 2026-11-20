-- Bateria de consultas avanzadas. Cada una: pregunta de negocio. Se imprimen como maximo unas filas para que el log sea legible.
\pset null '(nulo)'

\echo '=== GROUP BY + HAVING'
\echo 'Q01 Que tecnologias generaron mas de 5 000 GWh reales entre 2025-01 y 2026-10 y con cuantas plantas?'
SELECT t.nombre AS tecnologia, count(DISTINCT p.planta_id) AS plantas, round(sum(d.real_estimada_kwh) / 1e6, 1) AS real_gwh
FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id) JOIN energia.tecnologia t USING (tecnologia_id)
GROUP BY t.nombre HAVING sum(d.real_estimada_kwh) / 1e6 > 5000 ORDER BY real_gwh DESC;

\echo 'Q02 Que operadores (agentes) con 3 o mas plantas generaron mas de 500 GWh?'
SELECT a.codigo_sic, a.nombre, count(DISTINCT p.planta_id) AS plantas, round(sum(d.real_estimada_kwh) / 1e6, 1) AS real_gwh
FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id) JOIN energia.agente a ON a.codigo_sic = p.agente_codigo
GROUP BY a.codigo_sic, a.nombre HAVING count(DISTINCT p.planta_id) >= 3 AND sum(d.real_estimada_kwh) / 1e6 > 500 ORDER BY real_gwh DESC LIMIT 10;

\echo 'Q03 Que estaciones y sensores tienen menos del 80 % de los instantes que reporta el resto de la red? (referencia = instantes distintos del sensor)'
WITH rejilla AS (SELECT sensor_id, count(DISTINCT fecha_observacion) AS esperados FROM energia.observacion GROUP BY sensor_id)
SELECT e.codigo AS estacion, s.codigo AS sensor, count(*) AS instantes, r.esperados, round(100.0 * count(*) / r.esperados, 1) AS completitud_pct
FROM energia.observacion o JOIN rejilla r USING (sensor_id) JOIN energia.estacion e USING (estacion_id) JOIN energia.sensor s USING (sensor_id)
GROUP BY e.codigo, s.codigo, r.esperados HAVING count(*) < 0.8 * r.esperados ORDER BY completitud_pct LIMIT 10;

\echo '=== FUNCIONES DE VENTANA'
\echo 'Q04 Cual es el ranking mensual de plantas dentro de cada tecnologia por energia real? (RANK, top 3 de julio de 2026)'
SELECT * FROM (
  SELECT t.nombre AS tecnologia, p.codigo AS planta, date_trunc('month', d.fecha)::date AS mes, round(sum(d.real_estimada_kwh) / 1e6, 2) AS real_gwh,
         rank() OVER (PARTITION BY date_trunc('month', d.fecha), t.nombre ORDER BY sum(d.real_estimada_kwh) DESC) AS posicion
  FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id) JOIN energia.tecnologia t USING (tecnologia_id)
  WHERE d.fecha >= '2026-07-01' AND d.fecha < '2026-08-01'
  GROUP BY t.nombre, p.codigo, date_trunc('month', d.fecha)) r
WHERE posicion <= 3 ORDER BY tecnologia, posicion;

\echo 'Q05 Cuanto vario cada mes la generacion de las 5 plantas mas grandes frente al mes anterior? (LAG)'
WITH mensual AS (
  SELECT p.codigo, date_trunc('month', d.fecha)::date AS mes, sum(d.real_estimada_kwh) / 1e6 AS gwh
  FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id) GROUP BY 1, 2),
grandes AS (SELECT codigo FROM mensual GROUP BY codigo ORDER BY sum(gwh) DESC LIMIT 5)
SELECT codigo, mes, round(gwh, 2) AS gwh, round(lag(gwh) OVER w, 2) AS gwh_mes_anterior,
       round(100 * (gwh - lag(gwh) OVER w) / nullif(lag(gwh) OVER w, 0), 1) AS variacion_pct
FROM mensual WHERE codigo IN (SELECT codigo FROM grandes) WINDOW w AS (PARTITION BY codigo ORDER BY mes)
ORDER BY codigo, mes DESC LIMIT 10;

\echo 'Q06 Cual es el promedio movil de 7 dias de la planta de mayor generacion? (AVG OVER ROWS 6 PRECEDING, ultimos 5 dias)'
WITH top AS (SELECT planta_id FROM energia.generacion_diaria_planta GROUP BY planta_id ORDER BY sum(real_estimada_kwh) DESC LIMIT 1)
SELECT * FROM (
  SELECT p.codigo, d.fecha, d.real_estimada_kwh, round(avg(d.real_estimada_kwh) OVER (PARTITION BY d.planta_id ORDER BY d.fecha ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0) AS promedio_movil_7d
  FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id) WHERE d.planta_id IN (SELECT planta_id FROM top)) x
ORDER BY fecha DESC LIMIT 5;

\echo 'Q07 Que plantas con 1 GWh/dia o mas cayeron mas de 50 % frente a su promedio de los 30 dias anteriores? (ventana 30 PRECEDING..1 PRECEDING)'
SELECT * FROM (
  SELECT p.codigo, p.nombre, d.fecha, d.real_estimada_kwh,
         round(avg(d.real_estimada_kwh) OVER (PARTITION BY d.planta_id ORDER BY d.fecha ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING), 0) AS promedio_30d
  FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id) WHERE d.fecha >= '2026-09-01') x
WHERE promedio_30d >= 1000000 AND real_estimada_kwh < 0.5 * promedio_30d ORDER BY fecha DESC, promedio_30d DESC LIMIT 10;

\echo 'Q08 Cuantas plantas concentran el 80 % de la generacion de todo el periodo? (participacion acumulada SUM OVER)'
WITH total AS (SELECT p.codigo, sum(d.real_estimada_kwh) AS kwh FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id) GROUP BY p.codigo),
acum AS (SELECT codigo, kwh, row_number() OVER (ORDER BY kwh DESC) AS n,
                100 * sum(kwh) OVER (ORDER BY kwh DESC, codigo) / sum(kwh) OVER () AS acumulado_pct FROM total)
SELECT (SELECT count(*) FROM total) AS plantas_con_generacion, count(*) AS plantas_para_el_80_pct, round(max(acumulado_pct), 1) AS acumulado_pct
FROM acum WHERE n <= (SELECT min(n) FROM acum WHERE acumulado_pct >= 80);

\echo '=== JOINS'
\echo 'Q09 INNER: generacion del ultimo dia con planta, tecnologia, operador y capacidad vigente (hecho + 4 dimensiones)'
SELECT d.fecha, p.codigo, t.nombre AS tecnologia, a.nombre AS operador, d.real_estimada_kwh, c.capacidad_kw
FROM energia.generacion_diaria_planta d JOIN energia.planta p USING (planta_id) JOIN energia.tecnologia t USING (tecnologia_id)
JOIN energia.agente a ON a.codigo_sic = p.agente_codigo JOIN energia.capacidad_planta c ON c.planta_id = d.planta_id AND c.vigencia @> d.fecha
WHERE d.fecha = (SELECT max(fecha) FROM energia.generacion_diaria_planta) ORDER BY d.real_estimada_kwh DESC LIMIT 5;

\echo 'Q10 LEFT: que porcentaje de las estaciones del catalogo cruza con DIVIPOLA por nombre normalizado? (S-07)'
WITH est AS (SELECT DISTINCT ON (lpad(btrim(codigo), 10, '0')) lpad(btrim(codigo), 10, '0') AS codigo, departamento, municipio FROM staging.stg_estacion ORDER BY 1, fila_origen)
SELECT count(*) AS estaciones, count(m.codigo) AS con_cruce, round(100.0 * count(m.codigo) / count(*), 1) AS cruce_pct
FROM est e LEFT JOIN energia.departamento d ON d.nombre_normalizado = energia.normalizar_texto(e.departamento)
LEFT JOIN energia.municipio m ON m.departamento_codigo = d.codigo AND m.nombre_normalizado = energia.normalizar_texto(e.municipio);

\echo 'Q11 ANTI-JOIN: que plantas no tienen capacidad vigente al 2026-10-31, y cuales no tienen generacion diaria?'
SELECT 'sin capacidad vigente' AS caso, count(*) AS plantas FROM energia.planta p
WHERE NOT EXISTS (SELECT 1 FROM energia.capacidad_planta c WHERE c.planta_id = p.planta_id AND c.vigencia @> DATE '2026-10-31')
UNION ALL
SELECT 'sin generacion diaria', count(*) FROM energia.planta p
WHERE NOT EXISTS (SELECT 1 FROM energia.generacion_diaria_planta d WHERE d.planta_id = p.planta_id);

\echo 'Q12 FULL OUTER: que meses tiene XM, cuales UPME, y cuales solo uno de los dos? (cobertura)'
SELECT coalesce(x.mes, u.mes) AS mes, (x.mes IS NOT NULL) AS en_xm, (u.mes IS NOT NULL) AS en_upme
FROM (SELECT DISTINCT date_trunc('month', fecha)::date AS mes FROM energia.generacion_diaria_planta) x
FULL OUTER JOIN (SELECT DISTINCT periodo AS mes FROM energia.generacion_mensual_upme WHERE periodo >= '2025-01-01') u ON u.mes = x.mes
WHERE x.mes IS NULL OR u.mes IS NULL ORDER BY mes;

\echo 'Q13 LATERAL: cuales son las 3 horas pico de cada una de las 5 plantas solares con mas energia horaria?'
WITH solares AS (
  SELECT h.planta_id, sum(h.energia_kwh) AS kwh FROM energia.generacion_horaria_planta h JOIN energia.planta p USING (planta_id)
  JOIN energia.tecnologia t USING (tecnologia_id) WHERE t.nombre = 'SOLAR' GROUP BY h.planta_id ORDER BY 2 DESC LIMIT 5)
SELECT p.codigo, pico.fecha_hora AT TIME ZONE 'America/Bogota' AS hora_colombia, pico.energia_kwh, pico.version_codigo
FROM solares s JOIN energia.planta p USING (planta_id)
CROSS JOIN LATERAL (SELECT h.fecha_hora, h.energia_kwh, h.version_codigo FROM energia.generacion_horaria_planta h
                    WHERE h.planta_id = s.planta_id ORDER BY h.energia_kwh DESC LIMIT 3) pico
ORDER BY p.codigo, pico.energia_kwh DESC;

\echo 'Q14 JOIN POR TIEMPO: precipitacion diaria vs generacion hidraulica diaria (D14: se relacionan solo por dia, nunca por ubicacion)'
\echo '    Hoy devuelve 0 filas: las observaciones cubren 1 dia (2026-11-19) y la generacion diaria llega a 2026-10-31. Crece con el workflow de Actions.'
SELECT g.fecha, round(g.real_gwh, 1) AS hidraulica_gwh, round(l.precipitacion_mm, 1) AS precipitacion_mm
FROM (SELECT fecha, sum(real_estimada_kwh) / 1e6 AS real_gwh FROM analitica.v_generacion_diaria_tecnologia WHERE tecnologia = 'HIDRAULICA' GROUP BY fecha) g
JOIN (SELECT fecha, sum(suma) AS precipitacion_mm FROM analitica.v_clima_diario_departamento WHERE sensor = '0240' GROUP BY fecha) l USING (fecha)
ORDER BY g.fecha;
SELECT 'cobertura' AS dato, (SELECT min(fecha)::text || ' a ' || max(fecha)::text FROM energia.generacion_diaria_planta) AS generacion_diaria,
       (SELECT min(fecha_observacion AT TIME ZONE 'America/Bogota')::date::text || ' a ' || max(fecha_observacion AT TIME ZONE 'America/Bogota')::date::text FROM energia.observacion) AS observaciones;

\echo '=== VISTAS'
\echo 'V1 participacion UPME, ultimo mes (parcial)'
SELECT * FROM analitica.v_participacion_mensual_upme WHERE periodo = (SELECT max(periodo) FROM energia.generacion_mensual_upme) ORDER BY participacion_pct DESC LIMIT 5;
\echo 'V4 conciliacion XM vs UPME, julio de 2026'
SELECT * FROM analitica.v_conciliacion_xm_upme WHERE periodo = '2026-07-01' ORDER BY upme_gwh DESC NULLS LAST;
