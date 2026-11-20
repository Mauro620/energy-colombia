-- Plantas, capacidad, estaciones y sensores.

CREATE TABLE IF NOT EXISTS energia.planta (
  planta_id              integer      GENERATED ALWAYS AS IDENTITY,
  codigo                 char(4)      NOT NULL,
  nombre                 varchar(120) NOT NULL,
  tecnologia_id          smallint     NOT NULL,
  fuente_energetica_id   smallint     NOT NULL,
  clasificacion_id       smallint     NOT NULL,
  tipo_despacho          energia.tipo_despacho NOT NULL,
  agente_codigo          char(4)      NOT NULL,
  estado                 energia.estado_planta NOT NULL,
  fecha_inicio_operacion date         NOT NULL,
  CONSTRAINT pk_planta PRIMARY KEY (planta_id),
  CONSTRAINT uq_planta_codigo UNIQUE (codigo),
  CONSTRAINT fk_planta_tecnologia FOREIGN KEY (tecnologia_id)
    REFERENCES energia.tecnologia (tecnologia_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_planta_fuente_energetica FOREIGN KEY (fuente_energetica_id)
    REFERENCES energia.fuente_energetica (fuente_energetica_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_planta_clasificacion FOREIGN KEY (clasificacion_id)
    REFERENCES energia.clasificacion_recurso (clasificacion_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_planta_agente FOREIGN KEY (agente_codigo)
    REFERENCES energia.agente (codigo_sic) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS ix_planta_tecnologia ON energia.planta (tecnologia_id);
CREATE INDEX IF NOT EXISTS ix_planta_agente ON energia.planta (agente_codigo);

-- Capacidad vigente por rangos (D13). La capacidad no tiene sentido sin su planta: ON DELETE CASCADE.
CREATE TABLE IF NOT EXISTS energia.capacidad_planta (
  capacidad_id bigint        GENERATED ALWAYS AS IDENTITY,
  planta_id    integer       NOT NULL,
  vigencia     daterange     NOT NULL,
  capacidad_kw numeric(12,3) NOT NULL,
  CONSTRAINT pk_capacidad_planta PRIMARY KEY (capacidad_id),
  CONSTRAINT fk_capacidad_planta_planta FOREIGN KEY (planta_id)
    REFERENCES energia.planta (planta_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS energia.estacion (
  estacion_id            integer      GENERATED ALWAYS AS IDENTITY,
  codigo                 char(10)     NOT NULL,
  nombre                 varchar(200) NOT NULL,
  categoria_id           smallint     NOT NULL,
  tecnologia_estacion_id smallint     NOT NULL,
  estado                 energia.estado_estacion NOT NULL,
  municipio_codigo       char(5)      NOT NULL,
  entidad_id             integer      NOT NULL,
  zona_hidrografica_id   smallint,
  subzona_hidrografica   varchar(100),
  corriente              varchar(120),
  area_operativa         varchar(100),
  latitud                numeric(12,9) NOT NULL,
  longitud               numeric(12,9) NOT NULL,
  altitud                integer,
  fecha_instalacion      date,
  fecha_suspension       date,
  CONSTRAINT pk_estacion PRIMARY KEY (estacion_id),
  CONSTRAINT uq_estacion_codigo UNIQUE (codigo),
  CONSTRAINT fk_estacion_categoria FOREIGN KEY (categoria_id)
    REFERENCES energia.categoria_estacion (categoria_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_estacion_tecnologia FOREIGN KEY (tecnologia_estacion_id)
    REFERENCES energia.tecnologia_estacion (tecnologia_estacion_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_estacion_municipio FOREIGN KEY (municipio_codigo)
    REFERENCES energia.municipio (codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_estacion_entidad FOREIGN KEY (entidad_id)
    REFERENCES energia.entidad (entidad_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_estacion_zona_hidrografica FOREIGN KEY (zona_hidrografica_id)
    REFERENCES energia.zona_hidrografica (zona_hidrografica_id) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS ix_estacion_municipio ON energia.estacion (municipio_codigo);

CREATE TABLE IF NOT EXISTS energia.sensor (
  sensor_id    smallint     GENERATED ALWAYS AS IDENTITY,
  codigo       char(4)      NOT NULL,
  descripcion  varchar(150),
  unidad_id    smallint,
  valor_min    numeric(14,4),
  valor_max    numeric(14,4),
  centinelas   numeric(14,4)[] NOT NULL DEFAULT '{-9998,-9999}',
  CONSTRAINT pk_sensor PRIMARY KEY (sensor_id),
  CONSTRAINT uq_sensor_codigo UNIQUE (codigo),
  CONSTRAINT fk_sensor_unidad FOREIGN KEY (unidad_id)
    REFERENCES energia.unidad_medida (unidad_id) ON UPDATE CASCADE ON DELETE RESTRICT
);
