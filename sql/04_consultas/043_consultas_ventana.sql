-- Consultas con funciones de ventana. Una ventana calcula sobre un grupo de filas SIN colapsarlas (a diferencia de GROUP BY).
\pset null '(nulo)'

/* ---------------------------------------------------------------------
   Q04  Cuales son las 3 plantas con mas energia real de cada tecnologia en julio de 2026?
   Como: 1) CTE julio: suma la energia real por tecnologia y planta solo de julio.
         2) rank() numera las plantas de cada tecnologia de mayor a menor (PARTITION BY tecnologia).
         3) Se queda con las posiciones 1 a 3.
   Tecnica: RANK() OVER (PARTITION BY ... ORDER BY ...).
   --------------------------------------------------------------------- */
\echo '=== FUNCIONES DE VENTANA'
\echo 'Q04 Top 3 de plantas por tecnologia, julio 2026'
WITH julio AS (
  SELECT t.nombre AS tecnologia, p.codigo AS planta, sum(d.real_estimada_kwh) / 1e6 AS real_gwh
  FROM energia.generacion_diaria_planta d
  JOIN energia.planta p USING (planta_id)
  JOIN energia.tecnologia t USING (tecnologia_id)
  WHERE d.fecha >= '2026-07-01' AND d.fecha < '2026-08-01'
  GROUP BY t.nombre, p.codigo)
SELECT tecnologia, planta, round(real_gwh, 2) AS real_gwh, posicion
FROM (SELECT *, rank() OVER (PARTITION BY tecnologia ORDER BY real_gwh DESC) AS posicion FROM julio) r
WHERE posicion <= 3
ORDER BY tecnologia, posicion;

/* ---------------------------------------------------------------------
   Q05  Cuanto vario la generacion total de cada mes frente al mes anterior?
   Como: 1) CTE mensual: GWh totales por mes.
         2) lag(gwh) trae el valor de la fila anterior (el mes previo) y se calcula la variacion porcentual.
   Tecnica: LAG() OVER (ORDER BY mes).
   --------------------------------------------------------------------- */
\echo 'Q05 Variacion mensual de la generacion total'
WITH mensual AS (
  SELECT date_trunc('month', fecha)::date AS mes, sum(real_estimada_kwh) / 1e6 AS gwh
  FROM analitica.v_generacion_diaria_tecnologia
  GROUP BY 1)
SELECT mes, round(gwh, 1) AS gwh, round(lag(gwh) OVER w, 1) AS gwh_mes_anterior,
       round(100 * (gwh - lag(gwh) OVER w) / lag(gwh) OVER w, 1) AS variacion_pct
FROM mensual
WINDOW w AS (ORDER BY mes)
ORDER BY mes DESC
LIMIT 6;

/* ---------------------------------------------------------------------
   Q06  Cual es el promedio movil de 7 dias de la generacion total diaria?
   Como: 1) CTE diaria: GWh totales por dia.
         2) AVG() sobre la fila actual y las 6 anteriores (7 dias) suaviza las variaciones del dia a dia.
   Tecnica: AVG() OVER (ORDER BY fecha ROWS BETWEEN 6 PRECEDING AND CURRENT ROW).
   --------------------------------------------------------------------- */
\echo 'Q06 Promedio movil de 7 dias (ultimos 5 dias)'
WITH diaria AS (
  SELECT fecha, sum(real_estimada_kwh) / 1e6 AS gwh
  FROM analitica.v_generacion_diaria_tecnologia
  GROUP BY fecha)
SELECT fecha, round(gwh, 1) AS gwh,
       round(avg(gwh) OVER (ORDER BY fecha ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS promedio_movil_7d
FROM diaria
ORDER BY fecha DESC
LIMIT 5;

/* ---------------------------------------------------------------------
   Q07  Cuanta energia se ha generado acumulada en 2026, mes a mes?
   Como: 1) CTE mensual: GWh por mes de 2026.
         2) SUM() OVER (ORDER BY mes) suma el mes actual con todos los anteriores (total acumulado).
   Tecnica: SUM() OVER (ORDER BY ...) como acumulado.
   --------------------------------------------------------------------- */
\echo 'Q07 Generacion acumulada 2026'
WITH mensual AS (
  SELECT date_trunc('month', fecha)::date AS mes, sum(real_estimada_kwh) / 1e6 AS gwh
  FROM analitica.v_generacion_diaria_tecnologia
  WHERE fecha >= '2026-01-01'
  GROUP BY 1)
SELECT mes, round(gwh, 1) AS gwh, round(sum(gwh) OVER (ORDER BY mes), 1) AS acumulado_gwh
FROM mensual
ORDER BY mes;
