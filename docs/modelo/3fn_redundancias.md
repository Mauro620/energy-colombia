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
