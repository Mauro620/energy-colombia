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
