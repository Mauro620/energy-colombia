-- Consultas GROUP BY + HAVING (Q01 a Q03). Requiere las vistas.
-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d <base> -f 05_consultas_having.sql

-- ======================================================================
-- sql/04_consultas/042_consultas_having.sql
-- ======================================================================
-- Consultas con GROUP BY + HAVING. Cada una tiene un bloque con la pregunta, como funciona y la tecnica.
\pset null '(nulo)'

/* ---------------------------------------------------------------------
   Q01  Que tecnologias generaron mas de 5 000 GWh reales entre 2025-01 y 2026-10?
   Como: la vista v_generacion_diaria_tecnologia ya trae la energia por dia y tecnologia. Se suma por tecnologia
         (kWh / 1e6 = GWh) y HAVING deja solo las que pasan de 5 000.
   Tecnica: GROUP BY + HAVING sobre una suma.
   --------------------------------------------------------------------- */
\echo '=== GROUP BY + HAVING'
\echo 'Q01 Tecnologias con mas de 5 000 GWh reales'
SELECT tecnologia, round(sum(real_estimada_kwh) / 1e6, 1) AS real_gwh
FROM analitica.v_generacion_diaria_tecnologia
GROUP BY tecnologia
HAVING sum(real_estimada_kwh) / 1e6 > 5000
ORDER BY real_gwh DESC;

/* ---------------------------------------------------------------------
   Q02  Que operadores (agentes) tienen 3 o mas plantas?
   Como: cuenta las plantas de cada agente y HAVING conserva los que tienen 3 o mas.
   Tecnica: GROUP BY + HAVING sobre un conteo.
   --------------------------------------------------------------------- */
\echo 'Q02 Operadores con 3 o mas plantas'
SELECT a.codigo_sic, a.nombre, count(*) AS plantas
FROM energia.planta p
JOIN energia.agente a ON a.codigo_sic = p.agente_codigo
GROUP BY a.codigo_sic, a.nombre
HAVING count(*) >= 3
ORDER BY plantas DESC, a.nombre
LIMIT 10;

/* ---------------------------------------------------------------------
   Q03  Que departamentos tienen mas de 100 estaciones meteorologicas cargadas?
   Como: sigue estacion -> municipio -> departamento, cuenta estaciones por departamento y HAVING filtra los de mas de 100.
   Tecnica: GROUP BY + HAVING con dos JOIN.
   --------------------------------------------------------------------- */
\echo 'Q03 Departamentos con mas de 100 estaciones'
SELECT d.nombre AS departamento, count(*) AS estaciones
FROM energia.estacion e
JOIN energia.municipio m ON m.codigo = e.municipio_codigo
JOIN energia.departamento d ON d.codigo = m.departamento_codigo
GROUP BY d.nombre
HAVING count(*) > 100
ORDER BY estaciones DESC
LIMIT 10;
