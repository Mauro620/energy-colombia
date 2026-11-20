-- Entrega 1: vistas, consultas y bateria de pruebas (sql/04_consultas y 05_pruebas). Requiere la base cargada (sql/03_carga con data/stage).
-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f 02_consultas_y_pruebas.sql


-- ======================================================================
-- sql/04_consultas/041_vistas.sql
-- ======================================================================
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

-- ======================================================================
-- sql/04_consultas/042_consultas.sql
-- ======================================================================
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

-- ======================================================================
-- sql/05_pruebas/051_pruebas_reglas.sql
-- ======================================================================
-- Bateria de pruebas de reglas. Cada caso intenta una violacion (o una operacion valida) dentro de una subtransaccion que
-- SIEMPRE se revierte: la bateria no ensucia los datos. Imprime PASS/FAIL por caso con RAISE NOTICE y un resumen al final.
-- SQLSTATE esperados: 23514 CHECK, 23503 FK, 23505 UNIQUE, 23P01 EXCLUDE, P0001 trigger, 23502 NOT NULL, 22P02 ENUM, OK = debe entrar.
\set ON_ERROR_STOP on
\pset null '(nulo)'

CREATE TEMP TABLE resultados (n serial, regla text, caso text, esperado text, obtenido text, ok boolean);

CREATE FUNCTION pg_temp.probar(p_regla text, p_caso text, p_esperado text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_obtenido text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    v_obtenido := 'OK';                                        -- la variable sobrevive al rollback del bloque
    RAISE EXCEPTION 'rollback de la prueba' USING ERRCODE = 'RB001';
  EXCEPTION
    WHEN SQLSTATE 'RB001' THEN NULL;                           -- la sentencia funciono: se revierte
    WHEN OTHERS THEN v_obtenido := SQLSTATE;
  END;
  INSERT INTO resultados (regla, caso, esperado, obtenido, ok) VALUES (p_regla, p_caso, p_esperado, v_obtenido, v_obtenido = p_esperado);
  RAISE NOTICE '% | % | esperado % obtenido % -> %', p_regla, p_caso, p_esperado, v_obtenido, CASE WHEN v_obtenido = p_esperado THEN 'PASS' ELSE 'FAIL' END;
END $$;

\echo '=== CHECK (23514)'
SELECT pg_temp.probar('RN01', 'energia horaria negativa', '23514', $q$
  INSERT INTO energia.generacion_horaria_planta VALUES ((SELECT planta_id FROM energia.planta ORDER BY 1 LIMIT 1), '2030-01-01 05:00:00+00', -1, 'TX1') $q$);
SELECT pg_temp.probar('RN01', 'energia diaria real negativa', '23514', $q$
  INSERT INTO energia.generacion_diaria_planta VALUES ((SELECT planta_id FROM energia.planta ORDER BY 1 LIMIT 1), '2030-01-01', 0, 0, -5) $q$);
SELECT pg_temp.probar('RN01', 'UPME total negativo', '23514', $q$
  INSERT INTO energia.generacion_mensual_upme VALUES ('2030-01-01', (SELECT fuente_energetica_id FROM energia.fuente_energetica LIMIT 1), 1, 2, 1, -1, false) $q$);
SELECT pg_temp.probar('RN02', 'capacidad cero', '23514', $q$
  INSERT INTO energia.capacidad_planta (planta_id, vigencia, capacidad_kw) VALUES ((SELECT planta_id FROM energia.planta ORDER BY 1 LIMIT 1), '[2100-01-01,2100-02-01)', 0) $q$);
SELECT pg_temp.probar('RN02', 'vigencia vacia', '23514', $q$
  INSERT INTO energia.capacidad_planta (planta_id, vigencia, capacidad_kw) VALUES ((SELECT planta_id FROM energia.planta ORDER BY 1 LIMIT 1), 'empty', 10) $q$);
SELECT pg_temp.probar('RN04', 'hora no exacta (05:30)', '23514', $q$
  INSERT INTO energia.generacion_horaria_planta VALUES ((SELECT planta_id FROM energia.planta ORDER BY 1 LIMIT 1), '2030-01-01 05:30:00+00', 10, 'TX1') $q$);
SELECT pg_temp.probar('RN05', 'codigo de planta de 2 caracteres', '23514', $q$
  INSERT INTO energia.planta (codigo, nombre, tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion)
  SELECT 'AB', 'PRUEBA', tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion FROM energia.planta ORDER BY planta_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN05', 'codigo de planta en minuscula', '23514', $q$
  INSERT INTO energia.planta (codigo, nombre, tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion)
  SELECT 'abcd', 'PRUEBA', tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion FROM energia.planta ORDER BY planta_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN05', 'codigo de estacion de 5 digitos', '23514', $q$
  INSERT INTO energia.estacion (codigo, nombre, categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, latitud, longitud)
  SELECT '12345', 'PRUEBA', categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, 4.6, -74.1 FROM energia.estacion ORDER BY estacion_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN05', 'codigo de sensor con letras', '23514', $q$
  INSERT INTO energia.sensor (codigo) VALUES ('ab12') $q$);
SELECT pg_temp.probar('RN06', 'periodo UPME con dia 15', '23514', $q$
  INSERT INTO energia.generacion_mensual_upme VALUES ('2030-01-15', (SELECT fuente_energetica_id FROM energia.fuente_energetica LIMIT 1), 1, 2, 1, 5, false) $q$);
SELECT pg_temp.probar('RN07', 'estacion con latitud 40 (fuera de Colombia)', '23514', $q$
  INSERT INTO energia.estacion (codigo, nombre, categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, latitud, longitud)
  SELECT '9999999999', 'PRUEBA', categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, 40, -74.1 FROM energia.estacion ORDER BY estacion_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN08', 'municipio cuyo prefijo no es su departamento', '23514', $q$
  INSERT INTO energia.municipio (codigo, departamento_codigo, nombre, tipo) VALUES ('05999', '08', 'PRUEBA', 'Municipio') $q$);
SELECT pg_temp.probar('RN16', 'departamento con codigo no numerico', '23514', $q$
  INSERT INTO energia.departamento (codigo, nombre) VALUES ('A1', 'PRUEBA') $q$);
SELECT pg_temp.probar('RN12', 'suspension anterior a la instalacion', '23514', $q$
  INSERT INTO energia.estacion (codigo, nombre, categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, latitud, longitud, fecha_instalacion, fecha_suspension)
  SELECT '9999999999', 'PRUEBA', categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, 4.6, -74.1, '2020-01-01', '2019-01-01' FROM energia.estacion ORDER BY estacion_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN11', 'sensor con valor_max <= valor_min', '23514', $q$
  UPDATE energia.sensor SET valor_max = valor_min WHERE valor_min IS NOT NULL $q$);
SELECT pg_temp.probar('RN14', 'lote ok con contadores que no cuadran', '23514', $q$
  INSERT INTO control.carga_lote (fuente, tabla_destino, estado, finalizado_en, filas_leidas, filas_insertadas) VALUES ('prueba', 'x', 'ok', now(), 10, 3) $q$);

SELECT pg_temp.probar('RN07', 'departamento con latitud 40', '23514', $q$
  INSERT INTO energia.departamento (codigo, nombre, latitud, longitud) VALUES ('99', 'PRUEBA', 40, -74) $q$);
SELECT pg_temp.probar('RN07', 'municipio con longitud 10 (fuera de Colombia)', '23514', $q$
  INSERT INTO energia.municipio (codigo, departamento_codigo, nombre, tipo, latitud, longitud) VALUES ('05999', '05', 'PRUEBA', 'Municipio', 6, 10) $q$);
SELECT pg_temp.probar('RN07', 'estacion con altitud 7000 m', '23514', $q$
  INSERT INTO energia.estacion (codigo, nombre, categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, latitud, longitud, altitud)
  SELECT '9999999999', 'PRUEBA', categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, 4.6, -74.1, 7000 FROM energia.estacion ORDER BY estacion_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN05', 'codigo de agente de 2 caracteres', '23514', $q$
  INSERT INTO energia.agente VALUES ('AB', 'PRUEBA', 'GENERACION', 'OPERACION', '2020-01-01') $q$);
SELECT pg_temp.probar('RN05', 'codigo de version fuera de formato', '23514', $q$
  INSERT INTO energia.version_liquidacion VALUES ('ZZ9', 99, 'PRUEBA') $q$);
SELECT pg_temp.probar('RN16', 'codigo de municipio con letras', '23514', $q$
  INSERT INTO energia.municipio (codigo, departamento_codigo, nombre, tipo) VALUES ('0A999', '05', 'PRUEBA', 'Municipio') $q$);
SELECT pg_temp.probar('RN01', 'UPME con minimo mayor que el maximo', '23514', $q$
  INSERT INTO energia.generacion_mensual_upme VALUES ('2030-01-01', (SELECT fuente_energetica_id FROM energia.fuente_energetica LIMIT 1), 1, 2, 5, 5, false) $q$);
SELECT pg_temp.probar('RN11', 'sensor con valor_min pero sin valor_max', '23514', $q$
  INSERT INTO energia.sensor (codigo, valor_min) VALUES ('9998', 1) $q$);
SELECT pg_temp.probar('RN14', 'lote en_curso con fecha de fin', '23514', $q$
  INSERT INTO control.carga_lote (fuente, tabla_destino, estado, finalizado_en) VALUES ('prueba', 'x', 'en_curso', now()) $q$);
SELECT pg_temp.probar('RN14', 'lote cerrado antes de iniciar', '23514', $q$
  INSERT INTO control.carga_lote (fuente, tabla_destino, estado, iniciado_en, finalizado_en) VALUES ('prueba', 'x', 'error', now(), now() - interval '1 day') $q$);

\echo '=== EXCLUDE (23P01) y UNIQUE (23505)'
SELECT pg_temp.probar('RN03', 'vigencia solapada para la misma planta', '23P01', $q$
  INSERT INTO energia.capacidad_planta (planta_id, vigencia, capacidad_kw)
  SELECT planta_id, daterange(lower(vigencia), lower(vigencia) + 1), 100 FROM energia.capacidad_planta ORDER BY capacidad_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN03', 'vigencia contigua (no solapada) entra', 'OK', $q$
  INSERT INTO energia.capacidad_planta (planta_id, vigencia, capacidad_kw)
  SELECT planta_id, daterange(upper(vigencia) + 3650, upper(vigencia) + 3660), 100 FROM energia.capacidad_planta ORDER BY capacidad_id LIMIT 1 $q$);
SELECT pg_temp.probar('UQ', 'codigo de planta repetido', '23505', $q$
  INSERT INTO energia.planta (codigo, nombre, tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion)
  SELECT codigo, 'PRUEBA', tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion FROM energia.planta ORDER BY planta_id LIMIT 1 $q$);
SELECT pg_temp.probar('PK', 'misma (planta, hora) dos veces', '23505', $q$
  INSERT INTO energia.generacion_horaria_planta SELECT planta_id, fecha_hora, energia_kwh, version_codigo FROM energia.generacion_horaria_planta ORDER BY planta_id, fecha_hora LIMIT 1 $q$);
SELECT pg_temp.probar('RN13', 'dos lotes en_curso de la misma fuente', '23505', $q$
  DO $d$ BEGIN
    INSERT INTO control.carga_lote (fuente, tabla_destino) VALUES ('prueba', 'x');
    INSERT INTO control.carga_lote (fuente, tabla_destino) VALUES ('prueba', 'x');
  END $d$ $q$);

\echo '=== FK (23503), NOT NULL (23502) y ENUM (22P02)'
SELECT pg_temp.probar('FK', 'generacion diaria de una planta inexistente', '23503', $q$
  INSERT INTO energia.generacion_diaria_planta VALUES (-1, '2030-01-01', 1, 1, 1) $q$);
SELECT pg_temp.probar('FK', 'observacion de un sensor inexistente', '23503', $q$
  INSERT INTO energia.observacion VALUES ((SELECT estacion_id FROM energia.estacion ORDER BY 1 LIMIT 1), -1, '2030-01-01 05:00:00+00', 1) $q$);
SELECT pg_temp.probar('FK', 'observacion de una estacion inexistente (H18)', '23503', $q$
  INSERT INTO energia.observacion SELECT -1, sensor_id, '2030-01-01 05:00:00+00', 25 FROM energia.sensor WHERE codigo = '0068' $q$);
SELECT pg_temp.probar('FK', 'generacion horaria con version inexistente', '23503', $q$
  INSERT INTO energia.generacion_horaria_planta VALUES ((SELECT planta_id FROM energia.planta ORDER BY 1 LIMIT 1), '2030-01-01 05:00:00+00', 1, 'TXZ') $q$);
SELECT pg_temp.probar('FK', 'borrar una planta con generacion (ON DELETE RESTRICT)', '23503', $q$
  DELETE FROM energia.planta WHERE planta_id = (SELECT planta_id FROM energia.generacion_diaria_planta LIMIT 1) $q$);
SELECT pg_temp.probar('FK', 'borrar un departamento con municipios (RESTRICT)', '23503', $q$
  DELETE FROM energia.departamento WHERE codigo = '05' $q$);
SELECT pg_temp.probar('FK', 'borrar una planta sin hechos borra su capacidad (ON DELETE CASCADE)', 'OK', $q$
  DO $d$ DECLARE v int; BEGIN
    INSERT INTO energia.planta (codigo, nombre, tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion)
    SELECT 'ZZZ1', 'PRUEBA', tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion FROM energia.planta ORDER BY planta_id LIMIT 1
    RETURNING planta_id INTO v;
    INSERT INTO energia.capacidad_planta (planta_id, vigencia, capacidad_kw) VALUES (v, '[2100-01-01,2100-02-01)', 10);
    DELETE FROM energia.planta WHERE planta_id = v;
    IF EXISTS (SELECT 1 FROM energia.capacidad_planta WHERE planta_id = v) THEN RAISE EXCEPTION 'la capacidad no se borro en cascada'; END IF;
  END $d$ $q$);
SELECT pg_temp.probar('NN', 'planta sin nombre', '23502', $q$
  INSERT INTO energia.planta (codigo, nombre, tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion)
  SELECT 'ZZZ2', NULL, tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion FROM energia.planta ORDER BY planta_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN15', 'estado de planta fuera del ENUM', '22P02', $q$
  INSERT INTO energia.planta (codigo, nombre, tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, estado, fecha_inicio_operacion)
  SELECT 'ZZZ3', 'PRUEBA', tecnologia_id, fuente_energetica_id, clasificacion_id, tipo_despacho, agente_codigo, 'DESCONOCIDO', fecha_inicio_operacion FROM energia.planta ORDER BY planta_id LIMIT 1 $q$);

\echo '=== Triggers (P0001): RN09 version, RN10 capacidad, RN11 sensor'
SELECT pg_temp.probar('RN09', 'version de menor orden que la guardada (TXF -> TX1)', 'P0001', $q$
  UPDATE energia.generacion_horaria_planta SET version_codigo = 'TX1'
  WHERE (planta_id, fecha_hora) = (SELECT planta_id, fecha_hora FROM energia.generacion_horaria_planta WHERE version_codigo = 'TXF' LIMIT 1) $q$);
SELECT pg_temp.probar('RN09', 'version de mayor orden reemplaza (TXF -> TX4)', 'OK', $q$
  UPDATE energia.generacion_horaria_planta SET version_codigo = 'TX4'
  WHERE (planta_id, fecha_hora) = (SELECT planta_id, fecha_hora FROM energia.generacion_horaria_planta WHERE version_codigo = 'TXF' LIMIT 1) $q$);
SELECT pg_temp.probar('RN09', 'misma version, solo cambia la energia', 'OK', $q$
  UPDATE energia.generacion_horaria_planta SET energia_kwh = 0
  WHERE (planta_id, fecha_hora) = (SELECT planta_id, fecha_hora FROM energia.generacion_horaria_planta WHERE version_codigo = 'TXF' LIMIT 1) $q$);
SELECT pg_temp.probar('RN09', 'upsert con version inferior (ON CONFLICT DO UPDATE)', 'P0001', $q$
  INSERT INTO energia.generacion_horaria_planta
  SELECT planta_id, fecha_hora, energia_kwh, 'TX1' FROM energia.generacion_horaria_planta WHERE version_codigo = 'TXF' ORDER BY planta_id, fecha_hora LIMIT 1
  ON CONFLICT (planta_id, fecha_hora) DO UPDATE SET version_codigo = EXCLUDED.version_codigo $q$);
SELECT pg_temp.probar('RN10', 'energia mayor que capacidad x 1.10', 'P0001', $q$
  INSERT INTO energia.generacion_horaria_planta
  SELECT planta_id, '2025-06-01 10:00:00-05', capacidad_kw * 1.10 + 1, 'TX1' FROM energia.capacidad_planta WHERE vigencia @> DATE '2025-06-01' ORDER BY capacidad_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN10', 'energia igual a la capacidad entra', 'OK', $q$
  INSERT INTO energia.generacion_horaria_planta
  SELECT planta_id, '2025-06-01 10:00:00-05', capacidad_kw, 'TX1' FROM energia.capacidad_planta WHERE vigencia @> DATE '2025-06-01' ORDER BY capacidad_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN10', 'sin capacidad vigente el trigger no aplica', 'OK', $q$
  INSERT INTO energia.generacion_horaria_planta
  SELECT p.planta_id, '2025-06-01 10:00:00-05', 1000000, 'TX1' FROM energia.planta p
  WHERE NOT EXISTS (SELECT 1 FROM energia.capacidad_planta c WHERE c.planta_id = p.planta_id) ORDER BY p.planta_id LIMIT 1 $q$);
SELECT pg_temp.probar('RN11', 'temperatura fuera del rango del sensor (60 C)', 'P0001', $q$
  INSERT INTO energia.observacion SELECT (SELECT estacion_id FROM energia.estacion ORDER BY 1 LIMIT 1), sensor_id, '2030-01-01 05:00:00+00', 60 FROM energia.sensor WHERE codigo = '0068' $q$);
SELECT pg_temp.probar('RN11', 'centinela -9998 no entra como valor', 'P0001', $q$
  INSERT INTO energia.observacion SELECT (SELECT estacion_id FROM energia.estacion ORDER BY 1 LIMIT 1), sensor_id, '2030-01-01 05:00:00+00', -9998 FROM energia.sensor WHERE codigo = '0068' $q$);
SELECT pg_temp.probar('RN11', 'centinela propio del sensor (995 en temperatura)', 'P0001', $q$
  INSERT INTO energia.observacion SELECT (SELECT estacion_id FROM energia.estacion ORDER BY 1 LIMIT 1), sensor_id, '2030-01-01 05:00:00+00', 995 FROM energia.sensor WHERE codigo = '0068' $q$);
SELECT pg_temp.probar('RN11', 'temperatura valida (25.5 C)', 'OK', $q$
  INSERT INTO energia.observacion SELECT (SELECT estacion_id FROM energia.estacion ORDER BY 1 LIMIT 1), sensor_id, '2030-01-01 05:00:00+00', 25.5 FROM energia.sensor WHERE codigo = '0068' $q$);

\echo '=== Pruebas positivas de insercion valida'
SELECT pg_temp.probar('OK', 'estacion valida dentro de Colombia', 'OK', $q$
  INSERT INTO energia.estacion (codigo, nombre, categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, latitud, longitud)
  SELECT '9999999999', 'PRUEBA', categoria_id, tecnologia_estacion_id, estado, municipio_codigo, entidad_id, 4.6, -74.1 FROM energia.estacion ORDER BY estacion_id LIMIT 1 $q$);
SELECT pg_temp.probar('OK', 'generacion diaria valida', 'OK', $q$
  INSERT INTO energia.generacion_diaria_planta VALUES ((SELECT planta_id FROM energia.planta ORDER BY 1 LIMIT 1), '2030-01-01', 10, 10, 10) $q$);
SELECT pg_temp.probar('OK', 'periodo UPME dia 1', 'OK', $q$
  INSERT INTO energia.generacion_mensual_upme VALUES ('2030-01-01', (SELECT fuente_energetica_id FROM energia.fuente_energetica LIMIT 1), 1, 2, 1, 5, false) $q$);

\echo '=== RESUMEN'
SELECT n, regla, caso, esperado, obtenido, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado FROM resultados ORDER BY n;
SELECT count(*) AS casos, count(*) FILTER (WHERE ok) AS pass, count(*) FILTER (WHERE NOT ok) AS fail FROM resultados;

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
