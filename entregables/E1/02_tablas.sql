-- DDL: tipos, catalogos, entidades, hechos, control y staging. Base energia_db.
-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d <base> -f 02_tablas.sql

-- ======================================================================
-- sql/01_ddl/011_tipos.sql
-- ======================================================================
-- ENUM del modelo (RN15). Idempotente: CREATE TYPE no admite IF NOT EXISTS.
-- Dominios cerrados segun el perfil de las fuentes (hoja Dominios_ENUM del xlsx).
DO $$
DECLARE t record;
BEGIN
  FOR t IN SELECT * FROM (VALUES
      ('energia', 'estado_planta',   ARRAY['OPERACION', 'PRUEBAS']),
      ('energia', 'tipo_despacho',   ARRAY['DESPACHADO CENTRALMENTE', 'NO DESPACHADO CENTRALMENTE']),
      ('energia', 'estado_agente',   ARRAY['OPERACION', 'INACTIVO']),
      ('energia', 'estado_estacion', ARRAY['ACTIVA', 'SUSPENDIDA', 'EN MANTENIMIENTO']),
      ('control', 'estado_lote',     ARRAY['en_curso', 'ok', 'error'])
    ) v(esquema, nombre, valores)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_type ty JOIN pg_namespace n ON n.oid = ty.typnamespace
                   WHERE n.nspname = t.esquema AND ty.typname = t.nombre) THEN
      EXECUTE format('CREATE TYPE %I.%I AS ENUM (%s)', t.esquema, t.nombre,
                     (SELECT string_agg(quote_literal(x), ', ') FROM unnest(t.valores) x));
    END IF;
  END LOOP;
END $$;

-- ======================================================================
-- sql/01_ddl/012_catalogos.sql
-- ======================================================================
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

-- ======================================================================
-- sql/01_ddl/013_entidades.sql
-- ======================================================================
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

-- ======================================================================
-- sql/01_ddl/014_hechos.sql
-- ======================================================================
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

-- ======================================================================
-- sql/01_ddl/015_control.sql
-- ======================================================================
-- Bitacora de cargas (DQ07) y cuarentena (DQ05). Los registros rechazados pertenecen a su lote: ON DELETE CASCADE.

CREATE TABLE IF NOT EXISTS control.carga_lote (
  lote_id            bigint        GENERATED ALWAYS AS IDENTITY,
  fuente             varchar(60)   NOT NULL,
  tabla_destino      varchar(80)   NOT NULL,
  estado             control.estado_lote NOT NULL DEFAULT 'en_curso',
  iniciado_en        timestamptz   NOT NULL DEFAULT now(),
  finalizado_en      timestamptz,
  filas_leidas       bigint        NOT NULL DEFAULT 0,
  filas_insertadas   bigint        NOT NULL DEFAULT 0,
  filas_actualizadas bigint        NOT NULL DEFAULT 0,
  filas_omitidas     bigint        NOT NULL DEFAULT 0,
  filas_rechazadas   bigint        NOT NULL DEFAULT 0,
  mensaje            text,
  CONSTRAINT pk_carga_lote PRIMARY KEY (lote_id)
);

CREATE TABLE IF NOT EXISTS control.registro_rechazado (
  rechazo_id   bigint       GENERATED ALWAYS AS IDENTITY,
  lote_id      bigint       NOT NULL,
  regla        varchar(20)  NOT NULL,
  motivo       text         NOT NULL,
  registro     jsonb        NOT NULL,
  rechazado_en timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT pk_registro_rechazado PRIMARY KEY (rechazo_id),
  CONSTRAINT fk_registro_rechazado_lote FOREIGN KEY (lote_id)
    REFERENCES control.carga_lote (lote_id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS ix_registro_rechazado_lote_regla ON control.registro_rechazado (lote_id, regla);

-- ======================================================================
-- sql/01_ddl/016_staging.sql
-- ======================================================================
-- GENERADO por scripts/gen_modelo.py desde docs/modelo/modelo_er.dbml. No editar a mano.
-- Staging: todo en text, sin restricciones, para que la carga nunca rechace filas (D04). El orden de columnas
-- es el de los CSV de data/stage (pipeline/transform/aplanar.py).

CREATE TABLE IF NOT EXISTS staging.stg_listado_recursos (
  code text,
  name text,
  type text,
  disp text,
  rectype text,
  companycode text,
  enersource text,
  operstartdate text,
  state text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_agente (
  code text,
  name text,
  activity text,
  operstartdate text,
  state text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_capacidad (
  fecha text,
  codigo text,
  valor text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_gen_diaria (
  fecha text,
  codigoplanta text,
  tipogeneracion text,
  tipoclasificacion text,
  tipodespachorecurso text,
  generacionrealestimada text,
  generacionprogramadadespacho text,
  generacionprogramadaredespacho text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_gen_horaria (
  codigovariable text,
  fechahora text,
  codigoduracion text,
  unidadmedida text,
  codigosicagente text,
  codigoplanta text,
  version text,
  valor text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_divipola_dpto (
  codigo_departamento text,
  nombre_departamento text,
  longitud text,
  latitud text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_divipola_mpio (
  cod_dpto text,
  dpto text,
  cod_mpio text,
  nom_mpio text,
  tipo_municipio text,
  longitud text,
  latitud text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_estacion (
  codigo text,
  nombre text,
  categoria text,
  tecnologia text,
  estado text,
  departamento text,
  municipio text,
  altitud text,
  longitud text,
  latitud text,
  fecha_instalacion text,
  area_operativa text,
  corriente text,
  area_hidrografica text,
  zona_hidrografica text,
  subzona_hidrografica text,
  entidad text,
  fecha_suspension text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_observacion (
  codigoestacion text,
  codigosensor text,
  fechaobservacion text,
  valorobservado text,
  descripcionsensor text,
  unidadmedida text,
  archivo_origen text,
  fila_origen integer
);

CREATE TABLE IF NOT EXISTS staging.stg_upme (
  ano text,
  mes text,
  fuente text,
  promedio_mensual_gwh text,
  maximo_gwh text,
  minimo_gwh text,
  generacion_total_gwh text,
  porcentaje_participacion text,
  archivo_origen text,
  fila_origen integer
);
