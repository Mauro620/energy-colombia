# Diccionario de datos (E1)

_Generado por `scripts/gen_modelo.py` desde `modelo_er.dbml`. No editar a mano: editar el DBML y regenerar._

Columnas: **tabla**, **columna**, **tipo**, **nulos** (Si = admite NULL), **regla** (restricciones y codigo RNxx de `sql/02_reglas`), **origen** (`fuente.columna`; las fuentes estan en `docs/fuentes` y `data/raw`). `-` = surrogate o derivada.

## Esquema `energia`

| Tabla | Columna | Tipo | Nulos | Regla | Origen (fuente.columna) |
|---|---|---|---|---|---|
| departamento | codigo | char(2) | No | PK; CHECK 2 digitos (RN16) | divipola_vcjz-niiq.codigo_departamento |
| departamento | nombre | varchar(100) | No | UNIQUE; UNIQUE | divipola_vcjz-niiq.nombre_departamento |
| departamento | nombre_normalizado | varchar(100) | No | UNIQUE; derivada GENERATED: upper+unaccent+trim de nombre. Clave de cruce con IDEAM (DQ14). Redundancia deliberada: columna calculada, no puede desincronizarse | - |
| departamento | latitud | numeric(12,9) | Si | CHECK dentro de Colombia (RN07); la fuente usa coma decimal | divipola_vcjz-niiq.latitud |
| departamento | longitud | numeric(12,9) | Si | CHECK dentro de Colombia (RN07) | divipola_vcjz-niiq.longitud |
| municipio | codigo | char(5) | No | PK; CHECK 5 digitos y prefijo = departamento_codigo (RN08, H08) | divipola_gdxc-w37w.cod_mpio |
| municipio | departamento_codigo | char(2) | No | FK -> energia.departamento.codigo; FK ON UPDATE CASCADE ON DELETE RESTRICT | divipola_gdxc-w37w.cod_dpto |
| municipio | nombre | varchar(120) | No |  | divipola_gdxc-w37w.nom_mpio |
| municipio | nombre_normalizado | varchar(120) | No | derivada GENERATED (upper+unaccent+trim+sin puntuacion). UNIQUE con departamento_codigo | - |
| municipio | tipo | varchar(60) | No |  | divipola_gdxc-w37w.tipo_municipio |
| municipio | latitud | numeric(12,9) | Si | CHECK dentro de Colombia (RN07) | divipola_gdxc-w37w.latitud |
| municipio | longitud | numeric(12,9) | Si | CHECK dentro de Colombia (RN07) | divipola_gdxc-w37w.longitud |
| agente | codigo_sic | char(4) | No | PK; CHECK 4 caracteres alfanumericos. Dedup: 5 codigos repetidos, queda la fila OPERACION mas reciente (S-05) | xm_ListadoAgentes.Code |
| agente | nombre | varchar(200) | No | mayusculas | xm_ListadoAgentes.Name |
| agente | actividad | varchar(40) | No |  | xm_ListadoAgentes.Activity |
| agente | estado | energia.estado_agente | No | ENUM | xm_ListadoAgentes.State |
| agente | fecha_inicio_operacion | date | No |  | xm_ListadoAgentes.OperStartdate |
| tecnologia | tecnologia_id | smallint | No | PK; surrogate | - |
| tecnologia | nombre | varchar(30) | No | UNIQUE; UNIQUE, mayusculas (Solar=SOLAR). Coincide 1:1 con F01.TipoGeneracion | xm_ListadoRecursos.Type |
| clasificacion_recurso | clasificacion_id | smallint | No | PK; surrogate | - |
| clasificacion_recurso | nombre | varchar(40) | No | UNIQUE; UNIQUE, mayusculas | xm_ListadoRecursos.RecType |
| fuente_energetica | fuente_energetica_id | smallint | No | PK; surrogate | - |
| fuente_energetica | nombre | varchar(30) | No | UNIQUE; UNIQUE. Mapeo XM-UPME por igualdad de nombre (12 de 12 coinciden; OTROS solo existe en UPME) | xm_ListadoRecursos.EnerSource, socrata_tq63-itzr.fuente |
| fuente_energetica | en_xm | boolean | No | aparece en el listado de recursos de XM | - |
| fuente_energetica | en_upme | boolean | No | aparece en UPME | - |
| planta | planta_id | integer | No | PK; surrogate | - |
| planta | codigo | char(4) | No | UNIQUE; UNIQUE; CHECK 4 caracteres [A-Z0-9] (RN05, H06). Dedup: 3 codigos repetidos (S-04) | xm_ListadoRecursos.Code |
| planta | nombre | varchar(120) | No | mayusculas | xm_ListadoRecursos.Name |
| planta | tecnologia_id | smallint | No | FK -> energia.tecnologia.tecnologia_id; FK RESTRICT. Una sola tecnologia por planta (H06) | xm_ListadoRecursos.Type |
| planta | fuente_energetica_id | smallint | No | FK -> energia.fuente_energetica.fuente_energetica_id; FK RESTRICT | xm_ListadoRecursos.EnerSource |
| planta | clasificacion_id | smallint | No | FK -> energia.clasificacion_recurso.clasificacion_id; FK RESTRICT | xm_ListadoRecursos.RecType |
| planta | tipo_despacho | energia.tipo_despacho | No | ENUM | xm_ListadoRecursos.Disp |
| planta | agente_codigo | char(4) | No | FK -> energia.agente.codigo_sic; FK RESTRICT. Un operador por planta (H06). 149 de 149 codigos existen en ListadoAgentes | xm_ListadoRecursos.CompanyCode |
| planta | estado | energia.estado_planta | No | ENUM (Operacion=OPERACION) | xm_ListadoRecursos.State |
| planta | fecha_inicio_operacion | date | No |  | xm_ListadoRecursos.OperStartdate |
| capacidad_planta | capacidad_id | bigint | No | PK; surrogate | - |
| capacidad_planta | planta_id | integer | No | FK -> energia.planta.planta_id; FK ON DELETE CASCADE (la capacidad no existe sin la planta) | xm_CapEfecNeta.Code |
| capacidad_planta | vigencia | daterange | No | dias consecutivos con el mismo valor compactados en un rango [inicio, fin+1). EXCLUDE: sin solapes por planta (RN03) | xm_CapEfecNeta.Date |
| capacidad_planta | capacidad_kw | numeric(12,3) | No | CHECK > 0 (RN02, H03). Unidad kW segun ListadoMetricas | xm_CapEfecNeta.Value |
| version_liquidacion | codigo | varchar(3) | No | PK; CHECK ^TX[0-9FR]$ | simem_055A4D.Version |
| version_liquidacion | orden | smallint | No | UNIQUE; SUPUESTO S-01: TX1<TX2<TXR<TXF<TX3<TX4 (disponibilidad observada + noticias XM). CHECK > 0 | - |
| version_liquidacion | descripcion | varchar(200) | No | texto explicativo | - |
| generacion_diaria_planta | planta_id | integer | No | PK; FK -> energia.planta.planta_id; FK RESTRICT. Plantas fuera del listado van a cuarentena | simem_E17D25.CodigoPlanta |
| generacion_diaria_planta | fecha | date | No | PK; fecha de operacion (hora Colombia) | simem_E17D25.Fecha |
| generacion_diaria_planta | programada_despacho_kwh | numeric(18,4) | No | CHECK >= 0 (RN01, H01). Unidad kWh | simem_E17D25.GeneracionProgramadaDespacho |
| generacion_diaria_planta | programada_redespacho_kwh | numeric(18,4) | No | CHECK >= 0 (RN01, H01) | simem_E17D25.GeneracionProgramadaRedespacho |
| generacion_diaria_planta | real_estimada_kwh | numeric(18,4) | No | CHECK >= 0 (RN01, H01). Estimacion SCADA | simem_E17D25.GeneracionRealEstimada |
| generacion_horaria_planta | planta_id | integer | No | PK; FK -> energia.planta.planta_id; FK RESTRICT | simem_055A4D.CodigoPlanta |
| generacion_horaria_planta | fecha_hora | timestamptz | No | PK; hora exacta (RN04, H04); el origen es hora Colombia sin zona: se interpreta America/Bogota y se guarda en UTC (D11) | simem_055A4D.FechaHora |
| generacion_horaria_planta | energia_kwh | numeric(18,4) | No | CHECK >= 0 (RN01); trigger: <= capacidad vigente x 1.10 (RN10, H03) | simem_055A4D.Valor |
| generacion_horaria_planta | version_codigo | varchar(3) | No | FK -> energia.version_liquidacion.codigo; FK ON UPDATE CASCADE; trigger: solo reemplaza por version de orden igual o mayor (RN09, H02) | simem_055A4D.Version |
| generacion_mensual_upme | periodo | date | No | PK; make_date(ano, mes, 1); CHECK dia 1 (RN06) | socrata_tq63-itzr.ano,mes |
| generacion_mensual_upme | fuente_energetica_id | smallint | No | PK; FK -> energia.fuente_energetica.fuente_energetica_id; FK RESTRICT | socrata_tq63-itzr.fuente |
| generacion_mensual_upme | promedio_mensual_gwh | numeric(14,6) | No | CHECK >= 0 | socrata_tq63-itzr.promedio_mensual_gwh |
| generacion_mensual_upme | maximo_gwh | numeric(14,6) | No | CHECK >= 0 | socrata_tq63-itzr.maximo_gwh |
| generacion_mensual_upme | minimo_gwh | numeric(14,6) | No | CHECK >= 0 y <= maximo_gwh | socrata_tq63-itzr.minimo_gwh |
| generacion_mensual_upme | generacion_total_gwh | numeric(14,6) | No | CHECK >= 0 (RN01) | socrata_tq63-itzr.generacion_total_gwh |
| generacion_mensual_upme | parcial | boolean | No | true para el ultimo mes publicado (D09). Dato derivado de la carga: el mes puede completarse en publicaciones futuras | - |
| categoria_estacion | categoria_id | smallint | No | PK; surrogate | - |
| categoria_estacion | nombre | varchar(60) | No | UNIQUE; UNIQUE | socrata_hp9r-jxuu.categoria |
| tecnologia_estacion | tecnologia_estacion_id | smallint | No | PK; surrogate | - |
| tecnologia_estacion | nombre | varchar(60) | No | UNIQUE; UNIQUE. No es tecnologia de generacion | socrata_hp9r-jxuu.tecnologia |
| entidad | entidad_id | integer | No | PK; surrogate | - |
| entidad | nombre | varchar(200) | No | UNIQUE; UNIQUE | socrata_hp9r-jxuu.entidad |
| zona_hidrografica | zona_hidrografica_id | smallint | No | PK; surrogate | - |
| zona_hidrografica | area_hidrografica | varchar(60) | No |  | socrata_hp9r-jxuu.area_hidrografica |
| zona_hidrografica | nombre | varchar(80) | No |  | socrata_hp9r-jxuu.zona_hidrografica |
| estacion | estacion_id | integer | No | PK; surrogate | - |
| estacion | codigo | char(10) | No | UNIQUE; UNIQUE; CHECK 10 digitos (RN05, H14). El catalogo trae 8 o 10 digitos del mismo codigo: se normaliza con lpad a 10 (S-06) | socrata_hp9r-jxuu.codigo |
| estacion | nombre | varchar(200) | No |  | socrata_hp9r-jxuu.nombre |
| estacion | categoria_id | smallint | No | FK -> energia.categoria_estacion.categoria_id; FK RESTRICT | socrata_hp9r-jxuu.categoria |
| estacion | tecnologia_estacion_id | smallint | No | FK -> energia.tecnologia_estacion.tecnologia_estacion_id; FK RESTRICT | socrata_hp9r-jxuu.tecnologia |
| estacion | estado | energia.estado_estacion | No | ENUM | socrata_hp9r-jxuu.estado |
| estacion | municipio_codigo | char(5) | No | FK -> energia.municipio.codigo; FK RESTRICT; cruce por nombre normalizado con DIVIPOLA (D05); sin cruce = cuarentena | socrata_hp9r-jxuu.departamento,municipio |
| estacion | entidad_id | integer | No | FK -> energia.entidad.entidad_id; FK RESTRICT | socrata_hp9r-jxuu.entidad |
| estacion | zona_hidrografica_id | smallint | Si | FK -> energia.zona_hidrografica.zona_hidrografica_id; FK RESTRICT | socrata_hp9r-jxuu.area_hidrografica,zona_hidrografica |
| estacion | subzona_hidrografica | varchar(100) | Si | redundancia aceptada: subzona -> zona es una dependencia transitiva que se deja como texto (sin catalogo propio) por no tener otros atributos | socrata_hp9r-jxuu.subzona_hidrografica |
| estacion | corriente | varchar(120) | Si |  | socrata_hp9r-jxuu.corriente |
| estacion | area_operativa | varchar(100) | Si |  | socrata_hp9r-jxuu.area_operativa |
| estacion | latitud | numeric(12,9) | No | CHECK dentro de Colombia (RN07, H07, H15). ubicaci_n se descarta (invertida) | socrata_hp9r-jxuu.latitud |
| estacion | longitud | numeric(12,9) | No | CHECK dentro de Colombia (RN07, H07) | socrata_hp9r-jxuu.longitud |
| estacion | altitud | integer | Si | CHECK entre 0 y 6000 m | socrata_hp9r-jxuu.altitud |
| estacion | fecha_instalacion | date | Si | origen dd/mm/yyyy, to_date (H17, DQ11) | socrata_hp9r-jxuu.fecha_instalacion |
| estacion | fecha_suspension | date | Si | CHECK >= fecha_instalacion (RN12) | socrata_hp9r-jxuu.fecha_suspension |
| unidad_medida | unidad_id | smallint | No | PK; surrogate | - |
| unidad_medida | simbolo | varchar(10) | No | UNIQUE; UNIQUE | socrata_57sv-p2fu.unidadmedida |
| sensor | sensor_id | smallint | No | PK; surrogate | - |
| sensor | codigo | char(4) | No | UNIQUE; UNIQUE; CHECK 4 digitos (ceros a la izquierda) | socrata_57sv-p2fu.codigosensor |
| sensor | descripcion | varchar(150) | Si | nulo en el sensor 0245 (el origen no lo trae) | socrata_57sv-p2fu.descripcionsensor |
| sensor | unidad_id | smallint | Si | FK -> energia.unidad_medida.unidad_id; FK RESTRICT; nulo en 0245 | socrata_57sv-p2fu.unidadmedida |
| sensor | valor_min | numeric(14,4) | Si | rango plausible (D08), definido en docs/decisiones/0002; nulo en 0245 | - |
| sensor | valor_max | numeric(14,4) | Si | CHECK valor_max > valor_min (RN11) | - |
| sensor | centinelas | numeric(14,4)[] | No | valores que significan dato faltante (D08): -9998, -9999 y los propios del sensor | - |
| observacion | estacion_id | integer | No | PK; FK -> energia.estacion.estacion_id; FK RESTRICT; lpad 10 (S-06); huerfana = cuarentena (DQ15, H18) | socrata_57sv-p2fu.codigoestacion |
| observacion | sensor_id | smallint | No | PK; FK -> energia.sensor.sensor_id; FK RESTRICT | socrata_57sv-p2fu.codigosensor |
| observacion | fecha_observacion | timestamptz | No | PK; origen sin zona = America/Bogota (D11, DQ10); UTC al guardar | socrata_57sv-p2fu.fechaobservacion |
| observacion | valor | numeric(14,4) | No | centinelas no se cargan (DQ08); trigger: dentro del rango del sensor (RN11, DQ09) | socrata_57sv-p2fu.valorobservado |

- **energia.generacion_diaria_planta**: Una fila por planta y dia (H02). TipoGeneracion, TipoClasificacion y TipoDespachoRecurso de F01 no se guardan: dependen de la planta (3FN) y TipoClasificacion cambia en el tiempo en 252 plantas.
- **energia.generacion_horaria_planta**: Una fila por (planta, hora): la version vigente (D02-rev). El origen trae hasta 6 versiones por punto.
- **energia.generacion_mensual_upme**: porcentaje_participacion NO se almacena: se calcula en analitica.v_participacion_mensual_upme (D09, H12).
- **energia.observacion**: Una observacion por estacion, sensor e instante (H11).

## Esquema `control`

| Tabla | Columna | Tipo | Nulos | Regla | Origen (fuente.columna) |
|---|---|---|---|---|---|
| carga_lote | lote_id | bigint | No | PK; surrogate | - |
| carga_lote | fuente | varchar(60) | No | carpeta de data/raw o dataset (ej. simem_055A4D) | - |
| carga_lote | tabla_destino | varchar(80) | No | tabla del modelo que se carga | - |
| carga_lote | estado | control.estado_lote | No | ENUM. UNIQUE parcial: un solo lote en_curso por fuente (RN13) | - |
| carga_lote | iniciado_en | timestamptz | No | DEFAULT now() | - |
| carga_lote | finalizado_en | timestamptz | Si | nulo si y solo si en_curso; >= iniciado_en | - |
| carga_lote | filas_leidas | bigint | No | CHECK >= 0 | - |
| carga_lote | filas_insertadas | bigint | No | CHECK >= 0 | - |
| carga_lote | filas_actualizadas | bigint | No | CHECK >= 0 | - |
| carga_lote | filas_omitidas | bigint | No | repetidas o reemplazadas por version superior. CHECK >= 0 | - |
| carga_lote | filas_rechazadas | bigint | No | CHECK >= 0; en estado ok: leidas = insertadas + actualizadas + omitidas + rechazadas (RN14) | - |
| carga_lote | mensaje | text | Si | detalle del error o nota | - |
| registro_rechazado | rechazo_id | bigint | No | PK; surrogate | - |
| registro_rechazado | lote_id | bigint | No | FK -> control.carga_lote.lote_id; FK ON DELETE CASCADE (la cuarentena pertenece al lote) | - |
| registro_rechazado | regla | varchar(20) | No | codigo de la regla violada (RNxx, DQxx) | - |
| registro_rechazado | motivo | text | No | explicacion legible | - |
| registro_rechazado | registro | jsonb | No | fila de staging completa, sin modificar | - |
| registro_rechazado | rechazado_en | timestamptz | No | DEFAULT now() | - |

## Esquema `staging`

| Tabla | Columna | Tipo | Nulos | Regla | Origen (fuente.columna) |
|---|---|---|---|---|---|
| stg_listado_recursos | code | text | Si |  | xm_ListadoRecursos.Code |
| stg_listado_recursos | name | text | Si |  | xm_ListadoRecursos.Name |
| stg_listado_recursos | type | text | Si |  | xm_ListadoRecursos.Type |
| stg_listado_recursos | disp | text | Si |  | xm_ListadoRecursos.Disp |
| stg_listado_recursos | rectype | text | Si |  | xm_ListadoRecursos.RecType |
| stg_listado_recursos | companycode | text | Si |  | xm_ListadoRecursos.CompanyCode |
| stg_listado_recursos | enersource | text | Si |  | xm_ListadoRecursos.EnerSource |
| stg_listado_recursos | operstartdate | text | Si |  | xm_ListadoRecursos.OperStartdate |
| stg_listado_recursos | state | text | Si |  | xm_ListadoRecursos.State |
| stg_listado_recursos | archivo_origen | text | Si | ruta del .json.gz de data/raw (linaje) | - |
| stg_listado_recursos | fila_origen | integer | Si | posicion en el archivo (desempate al deduplicar) | - |
| stg_agente | code | text | Si |  | xm_ListadoAgentes.Code |
| stg_agente | name | text | Si |  | xm_ListadoAgentes.Name |
| stg_agente | activity | text | Si |  | xm_ListadoAgentes.Activity |
| stg_agente | operstartdate | text | Si |  | xm_ListadoAgentes.OperStartdate |
| stg_agente | state | text | Si |  | xm_ListadoAgentes.State |
| stg_agente | archivo_origen | text | Si |  | - |
| stg_agente | fila_origen | integer | Si |  | - |
| stg_capacidad | fecha | text | Si |  | xm_CapEfecNeta.Items.Date |
| stg_capacidad | codigo | text | Si |  | xm_CapEfecNeta.DailyEntities.Code |
| stg_capacidad | valor | text | Si |  | xm_CapEfecNeta.DailyEntities.Value |
| stg_capacidad | archivo_origen | text | Si |  | - |
| stg_capacidad | fila_origen | integer | Si |  | - |
| stg_gen_diaria | fecha | text | Si |  | simem_E17D25.Fecha |
| stg_gen_diaria | codigoplanta | text | Si |  | simem_E17D25.CodigoPlanta |
| stg_gen_diaria | tipogeneracion | text | Si |  | simem_E17D25.TipoGeneracion |
| stg_gen_diaria | tipoclasificacion | text | Si |  | simem_E17D25.TipoClasificacion |
| stg_gen_diaria | tipodespachorecurso | text | Si |  | simem_E17D25.TipoDespachoRecurso |
| stg_gen_diaria | generacionrealestimada | text | Si |  | simem_E17D25.GeneracionRealEstimada |
| stg_gen_diaria | generacionprogramadadespacho | text | Si |  | simem_E17D25.GeneracionProgramadaDespacho |
| stg_gen_diaria | generacionprogramadaredespacho | text | Si |  | simem_E17D25.GeneracionProgramadaRedespacho |
| stg_gen_diaria | archivo_origen | text | Si |  | - |
| stg_gen_diaria | fila_origen | integer | Si |  | - |
| stg_gen_horaria | codigovariable | text | Si |  | simem_055A4D.CodigoVariable |
| stg_gen_horaria | fechahora | text | Si |  | simem_055A4D.FechaHora |
| stg_gen_horaria | codigoduracion | text | Si |  | simem_055A4D.CodigoDuracion |
| stg_gen_horaria | unidadmedida | text | Si |  | simem_055A4D.UnidadMedida |
| stg_gen_horaria | codigosicagente | text | Si |  | simem_055A4D.CodigoSICAgente |
| stg_gen_horaria | codigoplanta | text | Si |  | simem_055A4D.CodigoPlanta |
| stg_gen_horaria | version | text | Si |  | simem_055A4D.Version |
| stg_gen_horaria | valor | text | Si |  | simem_055A4D.Valor |
| stg_gen_horaria | archivo_origen | text | Si |  | - |
| stg_gen_horaria | fila_origen | integer | Si |  | - |
| stg_divipola_dpto | codigo_departamento | text | Si |  | divipola_vcjz-niiq.codigo_departamento |
| stg_divipola_dpto | nombre_departamento | text | Si |  | divipola_vcjz-niiq.nombre_departamento |
| stg_divipola_dpto | longitud | text | Si |  | divipola_vcjz-niiq.longitud |
| stg_divipola_dpto | latitud | text | Si |  | divipola_vcjz-niiq.latitud |
| stg_divipola_dpto | archivo_origen | text | Si |  | - |
| stg_divipola_dpto | fila_origen | integer | Si |  | - |
| stg_divipola_mpio | cod_dpto | text | Si |  | divipola_gdxc-w37w.cod_dpto |
| stg_divipola_mpio | dpto | text | Si |  | divipola_gdxc-w37w.dpto |
| stg_divipola_mpio | cod_mpio | text | Si |  | divipola_gdxc-w37w.cod_mpio |
| stg_divipola_mpio | nom_mpio | text | Si |  | divipola_gdxc-w37w.nom_mpio |
| stg_divipola_mpio | tipo_municipio | text | Si |  | divipola_gdxc-w37w.tipo_municipio |
| stg_divipola_mpio | longitud | text | Si |  | divipola_gdxc-w37w.longitud |
| stg_divipola_mpio | latitud | text | Si |  | divipola_gdxc-w37w.latitud |
| stg_divipola_mpio | archivo_origen | text | Si |  | - |
| stg_divipola_mpio | fila_origen | integer | Si |  | - |
| stg_estacion | codigo | text | Si |  | socrata_hp9r-jxuu.codigo |
| stg_estacion | nombre | text | Si |  | socrata_hp9r-jxuu.nombre |
| stg_estacion | categoria | text | Si |  | socrata_hp9r-jxuu.categoria |
| stg_estacion | tecnologia | text | Si |  | socrata_hp9r-jxuu.tecnologia |
| stg_estacion | estado | text | Si |  | socrata_hp9r-jxuu.estado |
| stg_estacion | departamento | text | Si |  | socrata_hp9r-jxuu.departamento |
| stg_estacion | municipio | text | Si |  | socrata_hp9r-jxuu.municipio |
| stg_estacion | altitud | text | Si |  | socrata_hp9r-jxuu.altitud |
| stg_estacion | longitud | text | Si |  | socrata_hp9r-jxuu.longitud |
| stg_estacion | latitud | text | Si |  | socrata_hp9r-jxuu.latitud |
| stg_estacion | fecha_instalacion | text | Si |  | socrata_hp9r-jxuu.fecha_instalacion |
| stg_estacion | area_operativa | text | Si |  | socrata_hp9r-jxuu.area_operativa |
| stg_estacion | corriente | text | Si |  | socrata_hp9r-jxuu.corriente |
| stg_estacion | area_hidrografica | text | Si |  | socrata_hp9r-jxuu.area_hidrografica |
| stg_estacion | zona_hidrografica | text | Si |  | socrata_hp9r-jxuu.zona_hidrografica |
| stg_estacion | subzona_hidrografica | text | Si |  | socrata_hp9r-jxuu.subzona_hidrografica |
| stg_estacion | entidad | text | Si |  | socrata_hp9r-jxuu.entidad |
| stg_estacion | fecha_suspension | text | Si |  | socrata_hp9r-jxuu.fecha_suspension |
| stg_estacion | archivo_origen | text | Si |  | - |
| stg_estacion | fila_origen | integer | Si |  | - |
| stg_observacion | codigoestacion | text | Si |  | socrata_57sv-p2fu.codigoestacion |
| stg_observacion | codigosensor | text | Si |  | socrata_57sv-p2fu.codigosensor |
| stg_observacion | fechaobservacion | text | Si |  | socrata_57sv-p2fu.fechaobservacion |
| stg_observacion | valorobservado | text | Si |  | socrata_57sv-p2fu.valorobservado |
| stg_observacion | descripcionsensor | text | Si |  | socrata_57sv-p2fu.descripcionsensor |
| stg_observacion | unidadmedida | text | Si |  | socrata_57sv-p2fu.unidadmedida |
| stg_observacion | archivo_origen | text | Si |  | - |
| stg_observacion | fila_origen | integer | Si |  | - |
| stg_upme | ano | text | Si |  | socrata_tq63-itzr.ano |
| stg_upme | mes | text | Si |  | socrata_tq63-itzr.mes |
| stg_upme | fuente | text | Si |  | socrata_tq63-itzr.fuente |
| stg_upme | promedio_mensual_gwh | text | Si |  | socrata_tq63-itzr.promedio_mensual_gwh |
| stg_upme | maximo_gwh | text | Si |  | socrata_tq63-itzr.maximo_gwh |
| stg_upme | minimo_gwh | text | Si |  | socrata_tq63-itzr.minimo_gwh |
| stg_upme | generacion_total_gwh | text | Si |  | socrata_tq63-itzr.generacion_total_gwh |
| stg_upme | porcentaje_participacion | text | Si | se carga a staging solo para conciliar con la vista (D09); no pasa al modelo | socrata_tq63-itzr.porcentaje_participacion |
| stg_upme | archivo_origen | text | Si |  | - |
| stg_upme | fila_origen | integer | Si |  | - |

## Tipos ENUM

| Tipo | Valores |
|---|---|
| energia.estado_planta | OPERACION, PRUEBAS |
| energia.tipo_despacho | DESPACHADO CENTRALMENTE, NO DESPACHADO CENTRALMENTE |
| energia.estado_agente | OPERACION, INACTIVO |
| energia.estado_estacion | ACTIVA, SUSPENDIDA, EN MANTENIMIENTO |
| control.estado_lote | en_curso, ok, error |

## Normalizacion (3FN) y redundancias aceptadas

Cada tabla del esquema `energia` tiene una clave y todos sus atributos dependen de ella, de toda ella y solo de ella. Los atributos repetidos de las fuentes se separaron asi:

| Redundancia en la fuente | Tratamiento | Justificacion |
|---|---|---|
| F01 repite `TipoGeneracion`, `TipoClasificacion` y `TipoDespachoRecurso` en cada fila diaria | Se mueven a `planta` (tecnologia, clasificacion, tipo_despacho) desde `xm_ListadoRecursos`; no se guardan en el hecho | Dependen de la planta, no de (planta, fecha) |
| `TipoClasificacion` de F01 cambia en el tiempo en 252 plantas y mezcla vocabularios | No se guarda; se usa `RecType` del listado de recursos | No es una dependencia funcional estable de la planta |
| Observaciones IDEAM repiten nombre de estacion, departamento, municipio, zona, lat/lon | Se descartan de `observacion`; viven en `estacion` | Dependen de la estacion |
| `porcentaje_participacion` de UPME | No se almacena; vista `analitica.v_participacion_mensual_upme` | Derivable: `total_fuente / total_mes` (D09) |
| `departamento.nombre_normalizado`, `municipio.nombre_normalizado` | Columnas GENERATED STORED | Redundancia calculada por el motor: no puede desincronizarse |
| `estacion.subzona_hidrografica` determina la zona y el area (dependencia transitiva) | La zona y el area van en `zona_hidrografica`; la subzona queda como texto de `estacion` | La subzona no tiene atributos propios: un catalogo no agrega informacion |
| `generacion_mensual_upme.parcial` | Se guarda | Se calcula en la carga (ultimo mes publicado) y no es derivable luego de forma estable, porque el mes se completa en publicaciones futuras |
| `generacion_horaria_planta.version_codigo` junto a `version_liquidacion.orden` | Se guarda el codigo; el orden vive solo en el catalogo | Evita repetir el orden en 2.7 millones de filas |
| Version de liquidacion: el origen trae hasta 6 filas por (planta, hora) | Se guarda una sola fila: la de mayor orden | D02-rev |

