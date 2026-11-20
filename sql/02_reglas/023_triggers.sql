-- Triggers condicionales PL/pgSQL. Son la ultima defensa: la carga (sql/03_carga) filtra antes del INSERT.
-- Todos levantan SQLSTATE P0001 (RAISE EXCEPTION por defecto).

-- RN09 (H02) Version de liquidacion: si llega una version de MENOR orden que la guardada se rechaza; si es igual o mayor, se actualiza.
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
