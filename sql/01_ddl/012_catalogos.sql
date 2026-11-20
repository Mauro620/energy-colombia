-- Catalogos y geografia. Claves surrogate (identity) salvo donde la fuente trae una clave natural estable (DANE, SIC).
-- FK hacia catalogos: ON DELETE RESTRICT (un catalogo en uso no se borra) y ON UPDATE CASCADE (la clave natural puede corregirse).

-- ---- Geografia DIVIPOLA (D05)
CREATE TABLE IF NOT EXISTS energia.departamento (
  codigo              char(2)      NOT NULL,
  nombre              varchar(100) NOT NULL,
  nombre_normalizado  varchar(100) GENERATED ALWAYS AS (energia.normalizar_texto(nombre)) STORED NOT NULL,
  latitud             numeric(12,9),
  longitud            numeric(12,9),
  CONSTRAINT pk_departamento PRIMARY KEY (codigo),
  CONSTRAINT uq_departamento_nombre UNIQUE (nombre),
  CONSTRAINT uq_departamento_nombre_normalizado UNIQUE (nombre_normalizado)
);

CREATE TABLE IF NOT EXISTS energia.municipio (
  codigo              char(5)      NOT NULL,
  departamento_codigo char(2)      NOT NULL,
  nombre              varchar(120) NOT NULL,
  nombre_normalizado  varchar(120) GENERATED ALWAYS AS (energia.normalizar_texto(nombre)) STORED NOT NULL,
  tipo                varchar(60)  NOT NULL,
  latitud             numeric(12,9),
  longitud            numeric(12,9),
  CONSTRAINT pk_municipio PRIMARY KEY (codigo),
  CONSTRAINT fk_municipio_departamento FOREIGN KEY (departamento_codigo)
    REFERENCES energia.departamento (codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT uq_municipio_depto_nombre UNIQUE (departamento_codigo, nombre_normalizado)
);

-- ---- Catalogos de XM
CREATE TABLE IF NOT EXISTS energia.agente (
  codigo_sic              char(4)      NOT NULL,
  nombre                  varchar(200) NOT NULL,
  actividad               varchar(40)  NOT NULL,
  estado                  energia.estado_agente NOT NULL,
  fecha_inicio_operacion  date         NOT NULL,
  CONSTRAINT pk_agente PRIMARY KEY (codigo_sic)
);

CREATE TABLE IF NOT EXISTS energia.tecnologia (
  tecnologia_id smallint    GENERATED ALWAYS AS IDENTITY,
  nombre        varchar(30) NOT NULL,
  CONSTRAINT pk_tecnologia PRIMARY KEY (tecnologia_id),
  CONSTRAINT uq_tecnologia_nombre UNIQUE (nombre)
);

CREATE TABLE IF NOT EXISTS energia.clasificacion_recurso (
  clasificacion_id smallint    GENERATED ALWAYS AS IDENTITY,
  nombre           varchar(40) NOT NULL,
  CONSTRAINT pk_clasificacion_recurso PRIMARY KEY (clasificacion_id),
  CONSTRAINT uq_clasificacion_recurso_nombre UNIQUE (nombre)
);

CREATE TABLE IF NOT EXISTS energia.fuente_energetica (
  fuente_energetica_id smallint    GENERATED ALWAYS AS IDENTITY,
  nombre               varchar(30) NOT NULL,
  en_xm                boolean     NOT NULL DEFAULT false,
  en_upme              boolean     NOT NULL DEFAULT false,
  CONSTRAINT pk_fuente_energetica PRIMARY KEY (fuente_energetica_id),
  CONSTRAINT uq_fuente_energetica_nombre UNIQUE (nombre)
);

CREATE TABLE IF NOT EXISTS energia.version_liquidacion (
  codigo      varchar(3)   NOT NULL,
  orden       smallint     NOT NULL,
  descripcion varchar(200) NOT NULL,
  CONSTRAINT pk_version_liquidacion PRIMARY KEY (codigo),
  CONSTRAINT uq_version_liquidacion_orden UNIQUE (orden)
);

-- ---- Catalogos de IDEAM
CREATE TABLE IF NOT EXISTS energia.categoria_estacion (
  categoria_id smallint    GENERATED ALWAYS AS IDENTITY,
  nombre       varchar(60) NOT NULL,
  CONSTRAINT pk_categoria_estacion PRIMARY KEY (categoria_id),
  CONSTRAINT uq_categoria_estacion_nombre UNIQUE (nombre)
);

CREATE TABLE IF NOT EXISTS energia.tecnologia_estacion (
  tecnologia_estacion_id smallint    GENERATED ALWAYS AS IDENTITY,
  nombre                 varchar(60) NOT NULL,
  CONSTRAINT pk_tecnologia_estacion PRIMARY KEY (tecnologia_estacion_id),
  CONSTRAINT uq_tecnologia_estacion_nombre UNIQUE (nombre)
);

CREATE TABLE IF NOT EXISTS energia.entidad (
  entidad_id integer      GENERATED ALWAYS AS IDENTITY,
  nombre     varchar(200) NOT NULL,
  CONSTRAINT pk_entidad PRIMARY KEY (entidad_id),
  CONSTRAINT uq_entidad_nombre UNIQUE (nombre)
);

CREATE TABLE IF NOT EXISTS energia.zona_hidrografica (
  zona_hidrografica_id smallint    GENERATED ALWAYS AS IDENTITY,
  area_hidrografica    varchar(60) NOT NULL,
  nombre               varchar(80) NOT NULL,
  CONSTRAINT pk_zona_hidrografica PRIMARY KEY (zona_hidrografica_id),
  CONSTRAINT uq_zona_hidrografica UNIQUE (area_hidrografica, nombre)
);

CREATE TABLE IF NOT EXISTS energia.unidad_medida (
  unidad_id smallint    GENERATED ALWAYS AS IDENTITY,
  simbolo   varchar(10) NOT NULL,
  CONSTRAINT pk_unidad_medida PRIMARY KEY (unidad_id),
  CONSTRAINT uq_unidad_medida_simbolo UNIQUE (simbolo)
);
