-- Reglas de integridad: CHECK, EXCLUDE y triggers. Base energia_db.
-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d <base> -f 03_reglas.sql

-- ======================================================================
-- sql/02_reglas/020_helper.sql
-- ======================================================================
-- Ayuda para que las reglas sean idempotentes: agrega la restriccion solo si no existe.
CREATE OR REPLACE PROCEDURE control.agregar_restriccion(p_tabla regclass, p_nombre name, p_definicion text)
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = p_tabla AND conname = p_nombre) THEN
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s', p_tabla, p_nombre, p_definicion);
  END IF;
END $$;

-- ======================================================================
-- sql/02_reglas/021_checks.sql
-- ======================================================================
-- CHECK. Cada regla: codigo RNxx y la hipotesis Hxx de la hoja Hipotesis_reglas de la que sale.
-- Se aplican sobre tablas ya creadas; ADD CONSTRAINT valida las filas existentes (vacias en una base nueva).

-- RN16 (H08) Codigos DANE: departamento 2 digitos, municipio 5 digitos.
CALL control.agregar_restriccion('energia.departamento', 'ck_departamento_codigo', $$CHECK (codigo ~ '^[0-9]{2}$')$$);
CALL control.agregar_restriccion('energia.municipio', 'ck_municipio_codigo', $$CHECK (codigo ~ '^[0-9]{5}$')$$);

-- RN08 (H08) El codigo DANE del municipio empieza con el codigo de su departamento.
CALL control.agregar_restriccion('energia.municipio', 'ck_municipio_prefijo_depto', $$CHECK (left(codigo, 2) = departamento_codigo)$$);

-- RN05 (H06, H14, H21) Formato de codigos: planta y agente 4 caracteres; estacion 10 digitos (ceros a la izquierda); sensor 4 digitos.
CALL control.agregar_restriccion('energia.planta', 'ck_planta_codigo', $$CHECK (codigo ~ '^[A-Z0-9]{4}$')$$);
CALL control.agregar_restriccion('energia.agente', 'ck_agente_codigo', $$CHECK (codigo_sic ~ '^[A-Z0-9]{4}$')$$);
CALL control.agregar_restriccion('energia.estacion', 'ck_estacion_codigo', $$CHECK (codigo ~ '^[0-9]{10}$')$$);
CALL control.agregar_restriccion('energia.sensor', 'ck_sensor_codigo', $$CHECK (codigo ~ '^[0-9]{4}$')$$);
CALL control.agregar_restriccion('energia.version_liquidacion', 'ck_version_liquidacion_codigo', $$CHECK (codigo ~ '^TX[0-9FR]$')$$);

-- RN07 (H07) Coordenadas dentro de Colombia (caja que incluye las islas): latitud -5..16, longitud -84..-66 (S-10).
CALL control.agregar_restriccion('energia.estacion', 'ck_estacion_coordenadas',
  $$CHECK (latitud BETWEEN -5 AND 16 AND longitud BETWEEN -84 AND -66)$$);
CALL control.agregar_restriccion('energia.departamento', 'ck_departamento_coordenadas',
  $$CHECK ((latitud IS NULL OR latitud BETWEEN -5 AND 16) AND (longitud IS NULL OR longitud BETWEEN -84 AND -66))$$);
CALL control.agregar_restriccion('energia.municipio', 'ck_municipio_coordenadas',
  $$CHECK ((latitud IS NULL OR latitud BETWEEN -5 AND 16) AND (longitud IS NULL OR longitud BETWEEN -84 AND -66))$$);
CALL control.agregar_restriccion('energia.estacion', 'ck_estacion_altitud', $$CHECK (altitud IS NULL OR altitud BETWEEN 0 AND 6000)$$);

-- RN12 (H17) Una estacion no se suspende antes de instalarse.
CALL control.agregar_restriccion('energia.estacion', 'ck_estacion_fechas',
  $$CHECK (fecha_suspension IS NULL OR fecha_instalacion IS NULL OR fecha_suspension >= fecha_instalacion)$$);

-- RN01 (H01) La energia generada nunca es negativa.
CALL control.agregar_restriccion('energia.generacion_diaria_planta', 'ck_generacion_diaria_energia',
  $$CHECK (programada_despacho_kwh >= 0 AND programada_redespacho_kwh >= 0 AND real_estimada_kwh >= 0)$$);
CALL control.agregar_restriccion('energia.generacion_horaria_planta', 'ck_generacion_horaria_energia', $$CHECK (energia_kwh >= 0)$$);
CALL control.agregar_restriccion('energia.generacion_mensual_upme', 'ck_generacion_mensual_upme_energia',
  $$CHECK (promedio_mensual_gwh >= 0 AND maximo_gwh >= 0 AND minimo_gwh >= 0 AND generacion_total_gwh >= 0 AND minimo_gwh <= maximo_gwh)$$);

-- RN04 (H04) La resolucion temporal es horaria: minutos y segundos en cero (en UTC; Colombia no usa horario de verano).
CALL control.agregar_restriccion('energia.generacion_horaria_planta', 'ck_generacion_horaria_hora_exacta',
  $$CHECK (date_trunc('hour', fecha_hora AT TIME ZONE 'UTC') = fecha_hora AT TIME ZONE 'UTC')$$);

-- RN06 (H12) UPME: el periodo mensual se guarda como el dia 1.
CALL control.agregar_restriccion('energia.generacion_mensual_upme', 'ck_generacion_mensual_upme_periodo',
  $$CHECK (EXTRACT(day FROM periodo) = 1)$$);

-- RN02 (H03) La capacidad es positiva y la vigencia es un rango cerrado por abajo y no vacio.
CALL control.agregar_restriccion('energia.capacidad_planta', 'ck_capacidad_planta_capacidad', $$CHECK (capacidad_kw > 0)$$);
CALL control.agregar_restriccion('energia.capacidad_planta', 'ck_capacidad_planta_vigencia',
  $$CHECK (NOT isempty(vigencia) AND NOT lower_inf(vigencia) AND lower_inc(vigencia))$$);

-- RN11 (H10) Rango plausible por sensor: el maximo supera al minimo y ambos existen o ninguno.
CALL control.agregar_restriccion('energia.sensor', 'ck_sensor_rango',
  $$CHECK ((valor_min IS NULL) = (valor_max IS NULL) AND (valor_max IS NULL OR valor_max > valor_min))$$);

-- RN14 (DQ07) Contadores de un lote coherentes: no negativos, fin >= inicio, y un lote ok cuadra leidas = resto.
CALL control.agregar_restriccion('control.carga_lote', 'ck_carga_lote_contadores',
  $$CHECK (filas_leidas >= 0 AND filas_insertadas >= 0 AND filas_actualizadas >= 0 AND filas_omitidas >= 0 AND filas_rechazadas >= 0
           AND (estado <> 'ok' OR filas_leidas = filas_insertadas + filas_actualizadas + filas_omitidas + filas_rechazadas))$$);
CALL control.agregar_restriccion('control.carga_lote', 'ck_carga_lote_fechas',
  $$CHECK ((estado = 'en_curso') = (finalizado_en IS NULL) AND (finalizado_en IS NULL OR finalizado_en >= iniciado_en))$$);

-- Nota: las FK (RN17, H22 y H18: toda planta que genera y toda estacion que observa existe en su catalogo) estan en sql/01_ddl.
-- Los ENUM (RN15, H06) estan en sql/01_ddl/011_tipos.sql. UNIQUE de claves de negocio (H21, H11, H02) tambien estan en 01_ddl.

-- ======================================================================
-- sql/02_reglas/022_exclude_unico_parcial.sql
-- ======================================================================
-- RN03 (H20) Una planta tiene una sola capacidad vigente a la vez: sin vigencias solapadas. Requiere btree_gist.
CALL control.agregar_restriccion('energia.capacidad_planta', 'ex_capacidad_vigencia',
  'EXCLUDE USING gist (planta_id WITH =, vigencia WITH &&)');

-- RN13 (DQ07) Un solo lote en curso por fuente (UNIQUE parcial).
CREATE UNIQUE INDEX IF NOT EXISTS uq_carga_lote_en_curso ON control.carga_lote (fuente) WHERE estado = 'en_curso';

-- ======================================================================
-- sql/02_reglas/023_triggers.sql
-- ======================================================================
-- Triggers condicionales PL/pgSQL. Son la ultima defensa: la carga (sql/03_carga) filtra antes del INSERT.
-- Todos levantan SQLSTATE P0001 (RAISE EXCEPTION por defecto).

-- RN09 (H19) Version de liquidacion: si llega una version de MENOR orden que la guardada se rechaza; si es igual o mayor, se actualiza.
-- Condicional: solo se dispara cuando el UPDATE cambia la version (WHEN). Cubre INSERT ... ON CONFLICT DO UPDATE.
CREATE OR REPLACE FUNCTION energia.fn_generacion_horaria_version() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  orden_guardada smallint;
  orden_nueva    smallint;
BEGIN
  SELECT orden INTO orden_guardada FROM energia.version_liquidacion WHERE codigo = OLD.version_codigo;
  SELECT orden INTO orden_nueva    FROM energia.version_liquidacion WHERE codigo = NEW.version_codigo;
  IF orden_nueva < orden_guardada THEN
    RAISE EXCEPTION 'RN09: la version % (orden %) es anterior a la guardada % (orden %) para la planta % en %',
      NEW.version_codigo, orden_nueva, OLD.version_codigo, orden_guardada, NEW.planta_id, NEW.fecha_hora;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_generacion_horaria_version ON energia.generacion_horaria_planta;
CREATE TRIGGER trg_generacion_horaria_version
  BEFORE UPDATE ON energia.generacion_horaria_planta
  FOR EACH ROW WHEN (OLD.version_codigo IS DISTINCT FROM NEW.version_codigo)
  EXECUTE FUNCTION energia.fn_generacion_horaria_version();

-- RN10 (H03) La energia de una hora no supera la capacidad vigente x 1.10 (kW x 1 h = kWh; S-03).
-- Condicional: solo si la energia es positiva y existe capacidad vigente para la fecha (hora Colombia) de esa hora.
CREATE OR REPLACE FUNCTION energia.fn_generacion_horaria_capacidad() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  capacidad numeric;
BEGIN
  SELECT capacidad_kw INTO capacidad
    FROM energia.capacidad_planta
   WHERE planta_id = NEW.planta_id
     AND vigencia @> (NEW.fecha_hora AT TIME ZONE 'America/Bogota')::date;
  IF FOUND AND NEW.energia_kwh > capacidad * 1.10 THEN
    RAISE EXCEPTION 'RN10: % kWh superan la capacidad vigente % kW x 1.10 (planta %, %)',
      NEW.energia_kwh, capacidad, NEW.planta_id, NEW.fecha_hora;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_generacion_horaria_capacidad ON energia.generacion_horaria_planta;
CREATE TRIGGER trg_generacion_horaria_capacidad
  BEFORE INSERT OR UPDATE OF energia_kwh, fecha_hora, planta_id ON energia.generacion_horaria_planta
  FOR EACH ROW WHEN (NEW.energia_kwh > 0)
  EXECUTE FUNCTION energia.fn_generacion_horaria_capacidad();

-- RN11 (H10, H05, DQ08, DQ09) El valor de una observacion no es un centinela del sensor y esta dentro de su rango.
-- Condicional: sin rango (sensor 0245) solo se valida que no sea centinela.
CREATE OR REPLACE FUNCTION energia.fn_observacion_rango() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  s energia.sensor%ROWTYPE;
BEGIN
  SELECT * INTO s FROM energia.sensor WHERE sensor_id = NEW.sensor_id;
  IF NEW.valor = ANY (s.centinelas) THEN
    RAISE EXCEPTION 'RN11: % es un centinela de dato faltante del sensor %', NEW.valor, s.codigo;
  END IF;
  IF s.valor_min IS NOT NULL AND NEW.valor NOT BETWEEN s.valor_min AND s.valor_max THEN
    RAISE EXCEPTION 'RN11: % fuera del rango [%, %] del sensor %', NEW.valor, s.valor_min, s.valor_max, s.codigo;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_observacion_rango ON energia.observacion;
CREATE TRIGGER trg_observacion_rango
  BEFORE INSERT OR UPDATE OF valor, sensor_id ON energia.observacion
  FOR EACH ROW EXECUTE FUNCTION energia.fn_observacion_rango();
