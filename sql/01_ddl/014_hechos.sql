-- Hechos. FK hacia planta/estacion/sensor: ON DELETE RESTRICT (los hechos protegen a su dimension) y ON UPDATE CASCADE.

CREATE TABLE IF NOT EXISTS energia.generacion_diaria_planta (
  planta_id                integer       NOT NULL,
  fecha                    date          NOT NULL,
  programada_despacho_kwh  numeric(18,4) NOT NULL,
  programada_redespacho_kwh numeric(18,4) NOT NULL,
  real_estimada_kwh        numeric(18,4) NOT NULL,
  CONSTRAINT pk_generacion_diaria_planta PRIMARY KEY (planta_id, fecha),
  CONSTRAINT fk_generacion_diaria_planta_planta FOREIGN KEY (planta_id)
    REFERENCES energia.planta (planta_id) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS ix_generacion_diaria_fecha ON energia.generacion_diaria_planta (fecha);

CREATE TABLE IF NOT EXISTS energia.generacion_horaria_planta (
  planta_id      integer       NOT NULL,
  fecha_hora     timestamptz   NOT NULL,
  energia_kwh    numeric(18,4) NOT NULL,
  version_codigo varchar(3)    NOT NULL,
  CONSTRAINT pk_generacion_horaria_planta PRIMARY KEY (planta_id, fecha_hora),
  CONSTRAINT fk_generacion_horaria_planta_planta FOREIGN KEY (planta_id)
    REFERENCES energia.planta (planta_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_generacion_horaria_planta_version FOREIGN KEY (version_codigo)
    REFERENCES energia.version_liquidacion (codigo) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS ix_generacion_horaria_fecha_hora ON energia.generacion_horaria_planta (fecha_hora);

CREATE TABLE IF NOT EXISTS energia.generacion_mensual_upme (
  periodo                date          NOT NULL,
  fuente_energetica_id   smallint      NOT NULL,
  promedio_mensual_gwh   numeric(14,6) NOT NULL,
  maximo_gwh             numeric(14,6) NOT NULL,
  minimo_gwh             numeric(14,6) NOT NULL,
  generacion_total_gwh   numeric(14,6) NOT NULL,
  parcial                boolean       NOT NULL DEFAULT false,
  CONSTRAINT pk_generacion_mensual_upme PRIMARY KEY (periodo, fuente_energetica_id),
  CONSTRAINT fk_generacion_mensual_upme_fuente FOREIGN KEY (fuente_energetica_id)
    REFERENCES energia.fuente_energetica (fuente_energetica_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS energia.observacion (
  estacion_id       integer       NOT NULL,
  sensor_id         smallint      NOT NULL,
  fecha_observacion timestamptz   NOT NULL,
  valor             numeric(14,4) NOT NULL,
  CONSTRAINT pk_observacion PRIMARY KEY (estacion_id, sensor_id, fecha_observacion),
  CONSTRAINT fk_observacion_estacion FOREIGN KEY (estacion_id)
    REFERENCES energia.estacion (estacion_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_observacion_sensor FOREIGN KEY (sensor_id)
    REFERENCES energia.sensor (sensor_id) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS ix_observacion_sensor_fecha ON energia.observacion (sensor_id, fecha_observacion);
