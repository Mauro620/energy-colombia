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
