# Hallazgos de la fase de descubrimiento

_Generado por `pipeline/profiling/hallazgos.py` a partir de las muestras en `data/raw/` y las hojas del xlsx. No editar a mano._

## Datasets

| ID | Nombre | Rol detectado | Filas en origen | Filas en muestra |
|---|---|---|---|---|
| `vtmi-tusj` | Generación Real y Programada en las Plantas de Generación | xm | n/d | sin muestra |
| `8gum-9k6v` | Generación real | xm | n/d | sin muestra |
| `tq63-itzr` | Producción de electricidad por fuente de combustible | upme | 2786 | 2786 |
| `hp9r-jxuu` | Catálogo Nacional de Estaciones del IDEAM | ideam_cat | 57706 | 5000 |
| `57sv-p2fu` | Datos de Estaciones de IDEAM y de Terceros | ideam_obs | 156274 | 5000 |

## Preguntas P01-P16

### P01 (Generacion XM): Que representa una fila: planta-dia con columnas por hora, o planta-hora?

**Estado:** Si. **Respuesta tentativa:** Depende del dataset. F01 (`E17D25`): una fila = una planta en un dia, con las tres series como columnas. F02 (`055A4D`): una fila = una planta en una hora y una version de liquidacion (formato largo); no es planta-dia con columnas por hora.

**Evidencia:**

- `E17D25`: 381 filas, `CodigoPlanta` 381 distintos (unica), `Fecha` 1 valor distinto (2025-03-01).
- `055A4D`: 55344 filas = 385 plantas x 24 horas x 6 versiones (grilla completa = 55440, faltan 96; filas por version {'TX3': 9240, 'TX4': 9240, 'TXF': 9240, 'TXR': 9240, 'TX2': 9240, 'TX1': 9144}); (CodigoPlanta, FechaHora, Version) duplicados = 0.

### P02 (Generacion XM): En que unidad viene la energia (kWh, MWh, GWh)?

**Estado:** Si. **Respuesta tentativa:** XM entrega kWh en F01 y F02 (variables: `E17D25` GProgRedespacho=kWh, `E17D25` GeneracionRealEstimada=kWh, `E17D25` GProgDespacho=kWh, `055A4D` GReal=kWh); el valor se confirma en la columna `UnidadMedida` de F02. UPME publica en GWh (columnas `_gwh`). Mezclar XM y UPME exige convertir (1 GWh = 1 000 000 kWh).

**Evidencia:**

- `055A4D`.`UnidadMedida`: {'kWh': 55344} en 55344 filas.
- `E17D25`: sin columna de unidad; la unidad sale de `variables` de la respuesta de la API (3 variables, unidades ['kWh']).
- `tq63-itzr`: "Valor máximo de energía generada en un solo día del mes (GWh)."
- `tq63-itzr`: "Valor mínimo de energía generada en un solo día del mes (GWh)."
- `tq63-itzr`: columnas promedio_mensual_gwh, maximo_gwh, minimo_gwh, generacion_total_gwh (sufijo `_gwh`)

### P03 (Generacion XM): Que campo identifica la planta (codigo, nombre) y es igual en todos los datasets de XM?

**Estado:** Si. **Respuesta tentativa:** `CodigoPlanta` (texto corto) identifica la planta en F01 y F02. Hay solo codigo: SIMEM no trae el nombre de la planta (el nombre esta en `Name` del listado de recursos). Es el mismo campo en ambos datasets, con 4 plantas solo en F02.

**Evidencia:**

- `E17D25`: columnas ['Fecha', 'CodigoPlanta', 'TipoGeneracion', 'TipoClasificacion', 'TipoDespachoRecurso', 'GeneracionRealEstimada', 'GeneracionProgramadaDespacho', 'GeneracionProgramadaRedespacho']; `CodigoPlanta` longitudes [4], 381 distintos.
- `055A4D`: `CodigoPlanta` 385 distintos; en ambos 381; solo F01 0; solo F02 4 (2XXR, 3AL6, 3AXV, 3HWK).
- `055A4D`.`CodigoSICAgente`: 92 agentes (el listado de recursos usa `CompanyCode`, otro codigo de agente).

### P04 (Generacion XM): Hay valores negativos, nulos o ceros? Que significan segun la fuente?

**Estado:** Parcial. **Respuesta tentativa:** Hay datos en la muestra de IDEAM/UPME (lista en evidencia); su significado no sale de la muestra, solo de la descripcion de cada fuente. Para XM: no se puede responder con esta muestra.

**Evidencia:**

- `57sv-p2fu`.`valorobservado`: 7 negativos, 2002 ceros, 0.0% nulos en 5000 filas

### P05 (Generacion XM): Las series real, programada y redespacho vienen en el mismo dataset o separadas?

**Estado:** Si. **Respuesta tentativa:** Separadas por dataset y con forma distinta: F01 trae real, programada en despacho y programada en redespacho como tres columnas de la misma fila; F02 trae solo la real (`CodigoVariable` = GReal) por hora, y en varias versiones de liquidacion. El redespacho solo existe en F01.

**Evidencia:**

- `E17D25`: no nulos de GeneracionRealEstimada=381, GeneracionProgramadaDespacho=381, GeneracionProgramadaRedespacho=381 sobre 381 filas.
- `055A4D`: `CodigoVariable` {'GReal': 55344}; `Version` {'TX3': 9240, 'TX4': 9240, 'TXF': 9240, 'TXR': 9240, 'TX2': 9240, 'TX1': 9144}.

### P06 (Plantas): Donde esta la capacidad efectiva, la tecnologia, el operador y la ubicacion de cada planta?

**Estado:** Parcial. **Respuesta tentativa:** Parcial: el listado de recursos de XM trae tecnologia (`Type`, `EnerSource`) y agente (`CompanyCode`, un codigo, no el nombre), pero NO trae capacidad efectiva ni ubicacion. La capacidad esta en otra metrica (`CapEfecNeta`, por recurso, diaria, kW; no se ha llamado). La ubicacion de plantas no esta en ninguna fuente revisada.

**Evidencia:**

- `ListadoRecursos`: 2521 filas, columnas ['Code', 'Name', 'Type', 'Disp', 'RecType', 'CompanyCode', 'EnerSource', 'OperStartdate', 'State'].
- `Type` {'SOLAR': 2259, 'HIDRAULICA': 161, 'TERMICA': 82, 'COGENERADOR': 12, 'EOLICA': 7}; `CompanyCode` 149 distintos.

### P07 (Plantas): Con que llave se cruzan esos atributos con la generacion?

**Estado:** Si. **Respuesta tentativa:** `Code` del listado de recursos cruza con `CodigoPlanta`: 376 de 381 (98.7 %) en F01 y 379 de 385 (98.4 %) en F02. Los que no cruzan hay que revisarlos. `Code` no es unico (3 codigos repetidos, 2 con fila identica): hay que deduplicar antes de usarlo como llave.

**Evidencia:**

- F01 no cruzan: ['3IJF', '3KL4', '3RKN', '3RKP', '4SNT'].
- F02 no cruzan: ['3AL6', '3IJF', '3KL4', '3RKN', '3RKP', '4SNT'].
- `Code`: 2518 distintos en 2521 filas; repetidos ['5J8H', '5PUN', 'PRG1']; filas completamente duplicadas 2.
- Recursos del listado presentes en F01: 376 de 2518 (14.9 %).

### P08 (IDEAM): Que identifica una estacion y que columnas de ubicacion trae el catalogo?

**Estado:** Parcial. **Respuesta tentativa:** Catálogo Nacional de Estaciones del IDEAM (`hp9r-jxuu`): candidatas a identificar la estacion `codigo`, `nombre` (solo sobre muestra parcial). Ubicacion: `departamento`, `municipio`, `ubicaci_n`, `altitud`, `longitud`, `latitud`, `area_operativa`, `area_hidrografica`, `zona_hidrografica`, `subzona_hidrografica`.

**Evidencia:**

- `hp9r-jxuu`: 5000 de 57706 filas, columnas unicas en muestra: ['codigo', 'nombre']
- `hp9r-jxuu`: 99% de las filas traen en `ubicaci_n.latitude` el valor de la columna `longitud` (lat/long invertidas)

### P09 (IDEAM): Que sensores/variables hay, en que unidad y con que frecuencia?

**Estado:** Parcial. **Respuesta tentativa:** Datos de Estaciones de IDEAM y de Terceros (`57sv-p2fu`): 18 combinaciones sensor/descripcion/unidad en la muestra; la frecuencia va dentro del texto de `descripcionsensor` (horaria, cada 10 minutos), no en una columna propia.

**Evidencia:**

- `57sv-p2fu`: sensor 0027 | Humedad relativa del aire a 2 metros horaria | % | 240 filas
- `57sv-p2fu`: sensor 0068 | Temperatura del aire a 2 metros | °C | 89 filas
- `57sv-p2fu`: sensor 0069 | Temperatura máxima del Aire a 2 metros | °C | 131 filas
- `57sv-p2fu`: sensor 0070 | Temperatura mínima del Aire a 2 metros | °C | 65 filas
- `57sv-p2fu`: sensor 0103 | Velocidad del viento cada 10 minutos | m/s | 470 filas
- `57sv-p2fu`: sensor 0104 | Dirección del viento cada 10 minutos | deg | 427 filas
- `57sv-p2fu`: sensor 0230 | Nivel horario por sensor automático | cm | 142 filas
- `57sv-p2fu`: sensor 0231 | Nivel máximo horario | cm | 34 filas
- `57sv-p2fu`: sensor 0232 | Nivel mínimo horario | cm | 93 filas
- `57sv-p2fu`: sensor 0240 | Precipitación acumulada 10 minutos | mm | 1999 filas
- `57sv-p2fu`: sensor 0241 | Temperatura del suelo a 10 cm | °C | 6 filas
- `57sv-p2fu`: sensor 0242 | Temperatura del suelo a 30 cm | °C | 13 filas
- `57sv-p2fu`: sensor 0243 | Temperatura del suelo a 50 cm | °C | 411 filas
- `57sv-p2fu`: sensor 0245 | (nulo) | (nulo) | 14 filas
- `57sv-p2fu`: sensor 0246 | Humedad relativa del suelo a 30 cm horaria | % | 11 filas
- `57sv-p2fu`: sensor 0247 | Humedad relativa del suelo a 50 cm horaria | % | 710 filas
- `57sv-p2fu`: sensor 0255 | Presión atmosférica horaria | hPa | 88 filas
- `57sv-p2fu`: sensor 0260 | Evaporación total horaria | mm | 57 filas

### P10 (IDEAM): Cuantos registros hay en el periodo y departamentos de interes? Se puede filtrar desde la API?

**Estado:** Parcial. **Respuesta tentativa:** Datos de Estaciones de IDEAM y de Terceros (`57sv-p2fu`): 156274 filas; `fechaobservacion` 2026-11-19T10:11:00.000 a 2026-11-19T22:02:00.000. Catálogo Nacional de Estaciones del IDEAM (`hp9r-jxuu`): 57706 filas; sin columna de fecha de tipo fecha. El filtro `$where` por departamento no se probo contra el dataset completo desde este script.

**Evidencia:**

- `57sv-p2fu`.`departamento`: 33 distintos en la muestra; permite `$where` (ver `pipeline/config.yaml`)
- `hp9r-jxuu`.`departamento`: 33 distintos en la muestra; permite `$where` (ver `pipeline/config.yaml`)

### P11 (UPME): Que fuentes/combustibles publica y como se relacionan con las tecnologias de XM?

**Estado:** Parcial. **Respuesta tentativa:** Producción de electricidad por fuente de combustible (`tq63-itzr`): 13 fuentes: ACPM, AGUA, BAGAZO, BIOGAS, BIOMASA, CARBON, COMBUSTOLEO, GAS, GLP, JET-A1, OTROS, RAD SOLAR, VIENTO. Relacion con las tecnologias de XM: no se puede responder con esta muestra.

**Evidencia:**

- `tq63-itzr`.`fuente`: 13 distintos de 2786 filas

### P12 (UPME vs XM): Cubren el mismo periodo? Las cifras mensuales son comparables?

**Estado:** Parcial. **Respuesta tentativa:** UPME cubre 2000-01 a 2026-08 (en la muestra, 2786 de 2786 filas). Periodo de XM y comparabilidad mensual: no se puede responder con esta muestra.

**Evidencia:**

- `tq63-itzr`.`ano`/`mes`: minimo 2000-01, maximo 2026-08

### P13 (Todas): Las fechas estan en hora de Colombia o en UTC? En que formato vienen?

**Estado:** Si. **Respuesta tentativa:** SIMEM: `Fecha` (F01) es ISO `YYYY-MM-DD` y `FechaHora` (F02) es `YYYY-MM-DD HH:MM:SS`, ambas sin zona horaria. La generacion solar es maxima a las 11:00 y es 0 a las 00, 01, 02, 03, 04, 19, 20, 21, 22, 23 h, lo que corresponde a hora local de Colombia (un reloj UTC pondria el pico 5 h despues, hacia las 16:00). `57sv-p2fu`.`fechaobservacion`: el maximo (2026-11-19T22:02:00.000) esta a 1.2 h de la hora Colombia actual y a 6.2 h de la otra: sugiere hora Colombia.

**Evidencia:**

- `055A4D`.`FechaHora`: ejemplo `2025-03-01 12:00:00`, 24 horas distintas (0 a 23), `CodigoDuracion` ['PT1H'].
- Suma solar por hora en F02 (137 plantas solares de F01): 05h=2 MWh, 06h=400 MWh, 07h=3,155 MWh, 08h=6,360 MWh, 09h=8,337 MWh, 10h=9,359 MWh, 11h=9,606 MWh, 12h=8,805 MWh, 13h=8,821 MWh, 14h=9,188 MWh, 15h=7,524 MWh, 16h=5,273 MWh, 17h=1,313 MWh, 18h=9 MWh, 19h=0 MWh.
- `hp9r-jxuu`: fecha_instalacion, fecha_suspension vienen como texto (ej. `04/07/2018`)
- `57sv-p2fu`.`fechaobservacion`: tipo calendar_date, ejemplo `2026-11-19T10:11:00.000`, sin zona horaria en el valor

### P14 (Todas): Hay registros duplicados en origen? Con que combinacion de campos se detectan?

**Estado:** Parcial. **Respuesta tentativa:** Producción de electricidad por fuente de combustible (`tq63-itzr`): 0 duplicados exactos. Catálogo Nacional de Estaciones del IDEAM (`hp9r-jxuu`): 0 duplicados exactos. Datos de Estaciones de IDEAM y de Terceros (`57sv-p2fu`): 0 duplicados exactos. XM: no se puede responder con esta muestra. Una unicidad en muestra parcial no prueba unicidad en origen.

**Evidencia:**

- `tq63-itzr`: 0 filas duplicadas exactas en 2786 filas; columnas unicas ninguna; combinaciones candidatas ['ano, fuente, mes']
- `hp9r-jxuu`: 0 filas duplicadas exactas en 5000 filas; columnas unicas ['codigo', 'nombre']; combinaciones candidatas ninguna
- `57sv-p2fu`: 0 filas duplicadas exactas en 5000 filas; columnas unicas ninguna; combinaciones candidatas ['codigoestacion, fechaobservacion, codigosensor', 'nombreestacion, fechaobservacion, codigosensor']

### P15 (Ubicacion): Las fuentes usan codigos DANE, nombres de municipio o coordenadas?

**Estado:** Parcial. **Respuesta tentativa:** `hp9r-jxuu`: codigos DANE ninguno; nombres ['departamento', 'municipio']; coordenadas ['ubicaci_n', 'longitud', 'latitud']. `57sv-p2fu`: codigos DANE ninguno; nombres ['departamento', 'municipio']; coordenadas ['latitud', 'longitud']. XM: no se puede responder con esta muestra.

**Evidencia:**

- `tq63-itzr`: columnas de ubicacion []
- `hp9r-jxuu`: columnas de ubicacion ['departamento', 'municipio', 'ubicaci_n', 'longitud', 'latitud']
- `57sv-p2fu`: columnas de ubicacion ['departamento', 'municipio', 'latitud', 'longitud']

### P16 (Eventos): Existe un dataset abierto de mantenimientos o indisponibilidades de plantas?

**Estado:** No. **Respuesta tentativa:** no se puede responder con esta muestra: ninguna de las 5 fuentes es un dataset de mantenimientos o indisponibilidades de plantas; no se busco en el portal de XM ni en el catalogo de datos.gov.co.

**Evidencia:**

- Sin coincidencias en metadata de las 5 fuentes.

## Preguntas abiertas para el modelo

Cosas que podrian requerir una tabla o una decision; no se define ninguna tabla en esta fase.

- Las 2 fuentes de XM no son tablas Socrata: el equipo debe decidir si se consume la API de SIMEM (https://www.simem.co/datadetail/e17d259d-ffba-41f1-911c-d2b719a22efa, https://www.simem.co/datadetail/055a4d5f-3616-45e3-9bcd-1d3e3a4a47bd) y sobre que fuente se modela la generacion.
- `57sv-p2fu` cubre solo 2026-11-19T10:11:00.000 a 2026-11-19T22:02:00.000 (156274 filas): parece una ventana movil de lecturas recientes. Habra que acumular la historia por cuenta propia? Con que frecuencia?
- `57sv-p2fu`.`codigoestacion` trae ceros a la izquierda (ej. `0021208480`). Se cruza con `codigo` del catalogo, que aqui se ve sin ceros? Hay que normalizar el formato de la llave antes de cruzar.
- `hp9r-jxuu`: 99% de las filas traen en `ubicaci_n.latitude` el valor de la columna `longitud` (lat/long invertidas). Que columnas de ubicacion se toman como validas?
- UPME trae agregados mensuales por fuente (GWh) derivados de XM: guardarlos como tabla propia o recalcularlos desde la generacion de XM?

## Decisiones de la hoja `Decisiones` frente a la evidencia

Validada = la evidencia la respalda; REVISAR = la evidencia la contradice o la deja incompleta; Sin evidencia hoy = aun no se puede medir.

- **D01** (Validada con reservas): El datasetId es el prefijo de 6 caracteres (confirmado en F01 y F02). F01 trae las 3 series (0 nulos en 381 filas), `CodigoPlanta` y `Fecha`, en kWh. Enero 2025: 2 ventanas, 11471 filas, 31 de 31 dias con datos (sin datos: ninguno), 0 filas repetidas entre ventanas. Reserva: F02 pesa 0.36 MB gz por dia.
- **D02** (REVISAR): F01 no contiene la serie real de F02: F01 es diaria y F02 horaria; sumando las 24 horas de la version TXF solo 85 de 381 plantas coinciden con F01 (<= 1 kWh) aunque el total del dia difiere -0.18 %. F02 ademas tiene 6 versiones de liquidacion por punto y 4 plantas que F01 no tiene. F01 es una estimacion SCADA y F02 es liquidacion: son dos mediciones, no la misma serie.
- **D03** (Validada): 7 archivos ok en 5 manifiestos: sha256 del manifiesto = sha256 recalculado; 0 archivos sin cuadrar con el disco (sin entrada, sin archivo o hash distinto).
- **D04** (Sin evidencia hoy): Todavia no se carga a la base.
- **D05** (REVISAR): Ni los datasets de SIMEM ni `ListadoRecursos` traen municipio, departamento ni coordenadas (9 columnas del listado, ninguna geografica): DIVIPOLA sirve para IDEAM (nombres) pero las plantas de XM no tienen ubicacion que cruzar.
- **D06** (Validada en parte): ventana medida 2026-11-19T11:05:00.000 a 2026-11-19T22:57:00.000 = 11.9 h, 156981 filas; el workflow no se ha ejecutado en GitHub y el medidor de retraso de los cron no se midio.
- **D07** (Validada, con una tension): F01 enero 2025: 11471 filas -> ~247,552 filas en 669 dias. F02: 55344 filas/dia -> ~37,025,136 filas y ~243 MB gz en 669 dias. Con D02 (solo F01) el hecho tendria ~0.25 M filas, poco para ver diferencias en EXPLAIN (E3).
- **D08** (REVISAR): D08 solo nombra -9998/-9999. Con 156981 filas: -9998: 84 filas (sensores {'0027': 22, '0068': 22, '0069': 20, '0070': 20}); 999: 133 filas (sensores {'0104': 128, '0255': 5}); 995: 31 filas (sensores {'0068': 10, '0070': 10, '0069': 10, '0255': 1}); 1000: 133 filas (sensores {'0103': 129, '0255': 4}). Valores como 1000 m/s de viento o 995 C son fisicamente imposibles y parecen mas centinelas: faltan reglas por sensor.
- **D09** (Decidida (sin cambios)): No se toco UPME en esta sesion.
- **D10** (Validada): F01 y F02 en kWh segun `variables` y `UnidadMedida`; UPME en GWh (columnas `_gwh`).
- **D11** (Validada para SIMEM e IDEAM): La curva solar de F02 se alinea con hora local; en IDEAM el maximo de `fechaobservacion` coincide con la hora de Colombia (ver P13).
- **D12** (Sin cambios): Se usaron scripts + Makefile + Actions.
