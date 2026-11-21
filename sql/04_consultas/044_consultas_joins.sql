-- Consultas con distintos tipos de JOIN. Cada una indica el tipo de JOIN que usa y por que.
\pset null '(nulo)'

/* ---------------------------------------------------------------------
   Q08  Cuales fueron las 5 plantas con mas generacion el ultimo dia, con su tecnologia y su operador?
   Como: une la generacion con planta, tecnologia y agente. Solo el ultimo dia: fecha = (SELECT max(fecha)).
   Tecnica: INNER JOIN (solo filas que existen en todas las tablas).
   --------------------------------------------------------------------- */
\echo '=== JOINS'
\echo 'Q08 INNER JOIN: ultimo dia con planta, tecnologia y operador'
SELECT d.fecha, p.codigo AS planta, t.nombre AS tecnologia, a.nombre AS operador, d.real_estimada_kwh
FROM energia.generacion_diaria_planta d
JOIN energia.planta p USING (planta_id)
JOIN energia.tecnologia t USING (tecnologia_id)
JOIN energia.agente a ON a.codigo_sic = p.agente_codigo
WHERE d.fecha = (SELECT max(fecha) FROM energia.generacion_diaria_planta)
ORDER BY d.real_estimada_kwh DESC
LIMIT 5;

/* ---------------------------------------------------------------------
   Q09  Cuantos dias de generacion tiene cada planta? (incluidas las que no tienen ninguno)
   Como: parte de TODAS las plantas y les pega sus dias. Si una planta no tiene generacion, d.fecha queda nulo
         y count(d.fecha) da 0 (count(*) daria 1). Ordenado de menos a mas, salen primero las que no generaron.
   Tecnica: LEFT JOIN (conserva todo lo de la izquierda).
   --------------------------------------------------------------------- */
\echo 'Q09 LEFT JOIN: dias con generacion por planta (primero las que tienen 0)'
SELECT p.codigo AS planta, p.nombre, count(d.fecha) AS dias_con_generacion
FROM energia.planta p
LEFT JOIN energia.generacion_diaria_planta d USING (planta_id)
GROUP BY p.planta_id, p.codigo, p.nombre
ORDER BY dias_con_generacion, p.codigo
LIMIT 10;

/* ---------------------------------------------------------------------
   Q10  Que meses tiene XM, cuales UPME, y cuales solo uno de los dos?
   Como: lista los meses distintos de cada fuente y los une por mes. WHERE deja solo los que faltan en alguno.
   Tecnica: FULL OUTER JOIN (conserva lo que no cruza de ambos lados).
   --------------------------------------------------------------------- */
\echo 'Q10 FULL OUTER JOIN: meses que solo tiene XM o solo UPME'
SELECT coalesce(x.mes, u.mes) AS mes, (x.mes IS NOT NULL) AS en_xm, (u.mes IS NOT NULL) AS en_upme
FROM (SELECT DISTINCT date_trunc('month', fecha)::date AS mes FROM energia.generacion_diaria_planta) x
FULL OUTER JOIN (SELECT DISTINCT periodo AS mes FROM energia.generacion_mensual_upme WHERE periodo >= '2025-01-01') u ON u.mes = x.mes
WHERE x.mes IS NULL OR u.mes IS NULL
ORDER BY mes;

/* ---------------------------------------------------------------------
   Q11  Llovio mas los dias en que la generacion hidraulica fue mayor?
   Como: arma dos tablas por dia con las vistas (GWh hidraulicos y mm de lluvia del sensor 0240) y las une por fecha.
         Plantas y estaciones NO se relacionan por ubicacion (D14), solo por el dia.
   Tecnica: JOIN por fecha entre dos CTE.
   Nota: hoy devuelve 0 filas. Las observaciones cubren ~1 dia (2026-11-19) y la generacion diaria llega al 2026-10-31.
         La segunda consulta muestra esa cobertura.
   --------------------------------------------------------------------- */
\echo 'Q11 JOIN por fecha: lluvia vs generacion hidraulica (0 filas hoy, ver cobertura)'
WITH hidraulica AS (
  SELECT fecha, real_estimada_kwh / 1e6 AS gwh
  FROM analitica.v_generacion_diaria_tecnologia
  WHERE tecnologia = 'HIDRAULICA'),
lluvia AS (
  SELECT fecha, sum(suma) AS mm
  FROM analitica.v_clima_diario_departamento
  WHERE sensor = '0240'
  GROUP BY fecha)
SELECT fecha, round(h.gwh, 1) AS hidraulica_gwh, round(l.mm, 1) AS precipitacion_mm
FROM hidraulica h
JOIN lluvia l USING (fecha)
ORDER BY fecha;

SELECT (SELECT min(fecha) || ' a ' || max(fecha) FROM energia.generacion_diaria_planta) AS generacion_diaria,
       (SELECT min(fecha) || ' a ' || max(fecha) FROM analitica.v_clima_diario_departamento) AS observaciones;
