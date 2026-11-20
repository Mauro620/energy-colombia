-- Utilidades de carga: casts seguros (devuelven NULL en vez de fallar) y bitacora de lotes (DQ07).
-- Regla de la carga: lo que viola una regla se filtra ANTES del INSERT y va a control.registro_rechazado; los triggers son la ultima defensa.
--
-- Codigos de regla usados en registro_rechazado:
--   RN01 energia negativa | RN04 hora no exacta | RN05 formato de codigo | RN06 periodo UPME | RN07 coordenada/altitud fuera de rango
--   RN10 supera capacidad x 1.10 | RN11 fuera de rango del sensor | RN12 fechas incoherentes | RN15 valor fuera del ENUM
--   RN16 codigo DANE | RN17 referencia inexistente (planta, agente, estacion, sensor) | RN18 campo no convertible (fecha o numero)
--   RN19 clave duplicada con valores distintos | DQ08 centinela | DQ14 sin cruce con DIVIPOLA | DQ15 estacion huerfana

CREATE OR REPLACE FUNCTION control.a_numero(t text) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN btrim(t) ~ '^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$' THEN btrim(t)::numeric END
$$;

-- DIVIPOLA usa coma decimal.
CREATE OR REPLACE FUNCTION control.a_numero_coma(t text) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT control.a_numero(replace(t, ',', '.')) $$;

-- Fecha estricta sin excepciones (es rapida y paralelizable). Formatos: 'YYYY-MM-DD' (por defecto) y 'DD/MM/YYYY'. Fechas imposibles = NULL.
CREATE OR REPLACE FUNCTION control.a_fecha(t text, formato text DEFAULT 'YYYY-MM-DD') RETURNS date
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN p.y BETWEEN 1 AND 9999 AND p.m BETWEEN 1 AND 12 THEN
           CASE WHEN p.d BETWEEN 1 AND extract(day FROM (make_date(p.y, p.m, 1) + interval '1 month - 1 day'))::int
                THEN make_date(p.y, p.m, p.d) END
         END
    FROM (SELECT CASE WHEN formato = 'DD/MM/YYYY' THEN g[3] ELSE g[1] END::int AS y, g[2]::int AS m,
                 CASE WHEN formato = 'DD/MM/YYYY' THEN g[1] ELSE g[3] END::int AS d
            FROM (SELECT CASE WHEN formato = 'DD/MM/YYYY' THEN regexp_match(btrim(t), '^([0-9]{2})/([0-9]{2})/([0-9]{4})$')
                              ELSE regexp_match(btrim(t), '^([0-9]{4})-([0-9]{2})-([0-9]{2})$') END AS g) q
           WHERE g IS NOT NULL) p
$$;

CREATE OR REPLACE FUNCTION control.iniciar_lote(p_fuente text, p_tabla text) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE v_lote bigint;
BEGIN
  -- Un lote que quedo en_curso por una caida no debe bloquear al siguiente (RN13).
  UPDATE control.carga_lote SET estado = 'error', finalizado_en = clock_timestamp(), mensaje = 'cerrado por un lote nuevo'
   WHERE fuente = p_fuente AND estado = 'en_curso';
  INSERT INTO control.carga_lote (fuente, tabla_destino) VALUES (p_fuente, p_tabla) RETURNING lote_id INTO v_lote;
  RETURN v_lote;
END $$;

-- Cierra el lote. La restriccion ck_carga_lote_contadores exige leidas = insertadas + actualizadas + omitidas + rechazadas.
CREATE OR REPLACE FUNCTION control.cerrar_lote(p_lote bigint, p_leidas bigint, p_insertadas bigint, p_actualizadas bigint,
                                               p_omitidas bigint, p_rechazadas bigint, p_mensaje text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$
  UPDATE control.carga_lote
     SET estado = 'ok', finalizado_en = clock_timestamp(), filas_leidas = p_leidas, filas_insertadas = p_insertadas,
         filas_actualizadas = p_actualizadas, filas_omitidas = p_omitidas, filas_rechazadas = p_rechazadas, mensaje = p_mensaje
   WHERE lote_id = p_lote
$$;
