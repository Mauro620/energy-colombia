# 0002. Modelo y carga de la Entrega 1

- **Estado:** aceptada (los supuestos S-xx esperan validacion del equipo)
- **Fecha:** 2026-11-20
- **Evidencia:** `docs/fuentes/hallazgos.md`, `docs/fuentes/simem_*.md`, `docs/fuentes/xm_recursos.md`, hoja `Decisiones` del xlsx

## Decisiones aplicadas

| Cod. | Decision | Como queda en el modelo |
|---|---|---|
| D02-rev | Dos hechos de generacion, no uno. Reemplaza a D02 (que era falsa: F01 y F02 son dos mediciones distintas) | `generacion_diaria_planta` (E17D25: programada despacho, redespacho y real estimada) y `generacion_horaria_planta` (055A4D: una fila por planta y hora, la version vigente) |
| D07-rev | E17D25 y CapEfecNeta 2025-01-01 a 2026-10-31; 055A4D 2026-05-01 a 2026-10-31; UPME y catalogo IDEAM completos; observaciones IDEAM todo lo acumulado | `data/raw/` (ver `README.md`) |
| D13 | Capacidad por periodos de vigencia | `capacidad_planta(planta_id, vigencia daterange, capacidad_kw)` con `EXCLUDE` contra solapes. Dias consecutivos con el mismo valor forman un rango: 925 228 filas diarias quedan en 2 582 rangos |
| D14 | Sin relacion planta-estacion | XM no trae ubicacion de plantas (`ListadoRecursos` tiene 9 columnas y ninguna geografica). El clima y la generacion se relacionan **solo por tiempo** (dia u hora). **Limitacion:** no se puede decir que lluvia afecta a que planta |
| D05 | DIVIPOLA como maestro geografico | Descubierto por el catalogo de datos.gov.co: `gdxc-w37w` (1 122 municipios) y `vcjz-niiq` (33 departamentos), publicados por el DANE. Codigo DANE como PK natural |
| D08 | Centinelas no se cargan como valor | `-9998`, `-9999` mas los propios de cada sensor (`sensor.centinelas`); rango por sensor en `sensor.valor_min/valor_max` |
| D09 | UPME con `periodo date` y sin `porcentaje_participacion` | Vista `analitica.v_participacion_mensual_upme`; `parcial = true` para el ultimo mes publicado |
| D10, D11, D12 | Sin cambios | kWh (XM) y GWh (UPME) en el nombre de la columna; fechas sin zona = `America/Bogota`, guardadas en UTC |

## Supuestos que debe validar el equipo

| Cod. | Supuesto | Evidencia | Alternativa |
|---|---|---|---|
| **S-01** | Orden de las versiones de liquidacion: **TX1 < TX2 < TXR < TXF < TX3 < TX4** (la de mayor orden es la vigente). **SUPUESTO**: ni la metadata de SIMEM ni la documentacion de XM publican el orden | (a) En los meses recientes (2026-09 y 2026-10) solo existen TX1, TX2, TXR y TXF; TX3 aparece en los meses con 2 o mas meses de antiguedad y TX4 solo en meses mas viejos (en 2026-05 a 2026-10 no hay ninguna fila TX4; en 2025-03-01 si). (b) Noticias de XM: TX3 = "Ajuste #1" y TX4 = "Ajuste #2" de la liquidacion de un mes; TXR y TXF son las liquidaciones mensuales cercanas a la facturacion. Desconocido: el orden relativo entre TX1, TX2, TXR y TXF | Cambiar `energia.version_liquidacion.orden`: la carga y el trigger leen la tabla, no el codigo |
| S-02 | Rangos plausibles por sensor (`valor_min`, `valor_max`) y centinelas propios. Limites fisicos para humedad, temperatura (DQ09: -15 a 50 C), viento; para el resto, la envolvente real redondeada. Son **provisionales**: salen de un solo dia (~12 h) de datos | Tabla en `sql/03_carga/036_sensores.sql`, con min/max reales | Ajustar cuando se acumule historia (E3) |
| S-03 | La capacidad (kW) se asume constante durante la hora; energia horaria (kWh) <= capacidad x 1.10 (regla pedida) | 71 262 de 9 208 080 filas de 055A4D con capacidad la exceden (0.77 %); 884 de 246 886 en F01 (con capacidad x 24) | Subir o bajar la tolerancia |
| S-04 | `ListadoRecursos`: 3 codigos repetidos. 2 con filas identicas (`5J8H`, `5PUN`): queda una. `PRG1` tiene dos nombres (`PROELECTRICA`, `PROELECTRICA 1`): queda la **ultima fila** del listado | `docs/fuentes/xm_recursos.md` | Elegir `PROELECTRICA` |
| S-05 | `ListadoAgentes`: 5 codigos repetidos (`SPRG`, `NTCG`, `SOEC`, `EDQG`, `ETNC`): queda la fila `OPERACION` con `OperStartdate` mas reciente | 718 filas, 713 codigos | Conservar el historial en otra tabla |
| S-06 | Catalogo IDEAM: 57 706 filas son 9 935 estaciones. El mismo codigo viene con 10 y con 8 digitos (sin ceros) y filas repetidas. Se normaliza con `lpad` a 10 y queda la fila de 10 digitos de menor posicion. 44 estaciones tienen un `estado` distinto entre sus filas: no se reconcilia | 18 446 codigos crudos, 9 935 normalizados; 100 % de los 634 codigos de observaciones existen en el catalogo normalizado | Reconciliar por fecha (el catalogo no la trae) |
| S-07 | Cruce de estaciones con DIVIPOLA por (departamento, municipio) normalizados (upper, unaccent, trim, sin puntuacion). Lo que no cruza va a cuarentena, y con el sus observaciones | Cruce previo: 89.4 % de las estaciones (Bogota, Cali y Cucuta no cruzan por nombre). Ver el % real en `sql/05_pruebas` | Tabla de equivalencias manual (estaba en la hoja Decisiones y no en esta sesion) |
| S-08 | F01: 10 claves (planta, fecha) del recurso `ISGG` traen dos filas con valores distintos. Ambas van a cuarentena | `docs/fuentes/hallazgos.md` y control.registro_rechazado | Quedarse con la mayor |
| S-09 | Plantas de F01 (134) y F02 (40) que no estan en el listado de recursos van a cuarentena. Incluye codigos que no son plantas (`Grp3062`, `Unt0557`, `54091`) | Conteo en control.registro_rechazado | Cargarlas con los atributos nulos |
| S-10 | Coordenadas validas: latitud entre -5 y 16, longitud entre -84 y -66 (caja que incluye las islas); altitud entre 0 y 6000 m | Catalogo: lat -4.28 a 15.80, lon -83.06 a -66.83 | Poligono real de Colombia |
| S-11 | La vigencia de capacidad termina en el ultimo dia extraido (2026-10-31); no se extrapola | CapEfecNeta 2025-01-01 a 2026-10-31 | Dejar el ultimo rango abierto |

## Hallazgos de los datos que cambian algo (no contradicen las decisiones)

- F01 y F02 no son la misma serie: solo 85 de 381 plantas coinciden entre F01 y la suma horaria de F02 (version TXF); los totales difieren -0.18 %. Es la razon de D02-rev.
- F01 trae filas duplicadas por solapes entre mis ventanas (Jan-31 y Mar-01): son identicas y se omiten por `ON CONFLICT`; los lotes las cuentan como omitidas.
- F01 trae 1 fila con `CodigoPlanta` vacio (2025-02-14) y codigos de 5 a 7 caracteres: cuarentena.
- 220 plantas de F01 no tienen ninguna capacidad en CapEfecNeta; el trigger de capacidad no aplica a ellas.
- UPME: agosto de 2026 suma 2 455 GWh frente a 7 000-7 700 de los meses anteriores: parcial (D09).

## Limitaciones

1. No hay relacion geografica entre plantas y estaciones (D14).
2. `observacion` cubre solo lo acumulado hasta el dia de la carga: ~12 h. La historia crece con el workflow de Actions (D06).
3. 055A4D cubre 6 meses (2026-05 a 2026-10); se amplia en E3.
4. Los rangos de sensores son provisionales (S-02).
