-- Entrega 1: setup + DDL + reglas (sql/00_setup, 01_ddl y 02_reglas). Parte de una base vacia; es idempotente.
-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f 01_ddl_energia.sql


-- ======================================================================
-- sql/00_setup/001_base.sql
-- ======================================================================
-- Idempotente. CREATE DATABASE no admite IF NOT EXISTS: se usa \gexec.
SELECT 'CREATE DATABASE energia_db'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'energia_db')\gexec

\connect energia_db

REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- ======================================================================
-- sql/00_setup/002_esquemas_extensiones.sql
-- ======================================================================
-- Esquemas y extensiones de energia_db. Idempotente. Ejecutar con: psql -v ON_ERROR_STOP=1 -f ...
-- staging = texto crudo aplanado; energia = modelo; control = cargas y cuarentena; analitica = solo vistas.
\connect energia_db

CREATE EXTENSION IF NOT EXISTS btree_gist;  -- EXCLUDE con igualdad de entero + solape de rango (ex_capacidad_vigencia)
CREATE EXTENSION IF NOT EXISTS unaccent;    -- claves de cruce geografico sin tildes (D05, DQ14)

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS energia;
CREATE SCHEMA IF NOT EXISTS control;
CREATE SCHEMA IF NOT EXISTS analitica;

-- upper + unaccent + trim + puntuacion a espacio. Declarada IMMUTABLE (unaccent con diccionario fijo no cambia)
-- para poder usarla en columnas GENERATED. 'Bogota, D.C' -> 'BOGOTA D C'.
CREATE OR REPLACE FUNCTION energia.normalizar_texto(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS $$
  SELECT btrim(regexp_replace(upper(public.unaccent('public.unaccent'::regdictionary, t)), '[[:punct:][:space:]]+', ' ', 'g'))
$$;

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
