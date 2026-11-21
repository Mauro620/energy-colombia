# SIMEM `E17D25`: Generación Real y Programada en las Plantas de Generación

_Generado por `pipeline/extract/simem_explorar.py`. No editar a mano._

- **Origen:** Socrata `vtmi-tusj` (entrada federada) -> https://www.simem.co/datadetail/e17d259d-ffba-41f1-911c-d2b719a22efa
- **Hipotesis del datasetId** (primeros 6 caracteres del uuid, en mayusculas = `E17D25`): CONFIRMADA: la API devuelve `idDataset = E17D25` y el mismo nombre que Socrata.
- **Endpoint:** `GET https://www.simem.co/backend-files/api/PublicData?datasetId=&startDate=&endDate=` (fecha ISO, `endDate` inclusiva: 2 dias dan el doble de filas).
- **Dia extraido:** 2025-03-01 -> 381 filas. Periodicidad Diaria, granularidad Diaria, ultima actualizacion 2026-11-19 14:12:46.
- **Descripcion:** Contiene para las plantas del Sistema Interconectado Nacional (SIN) generación programada en el despacho, generación programada en el redespacho y generación real.
- **Columna de fecha del filtro (`filterDate`):** Fecha

## Mayusculas de los parametros (prueba hecha con el dataset mas liviano)

- datasetId/startDate/endDate (camelCase): success=True, 381 filas
- datasetid/startdate/enddate (minusculas): success=True, 381 filas
- DatasetId/StartDate/EndDate (PascalCase): success=True, 381 filas
- datasetId en minusculas (valor): success=True, 381 filas

## Columnas

| Columna | Tipo (API) | Tipo en el JSON | Ejemplo | Nulos | Distintos | Minimo | Maximo | Descripcion (API) |
|---|---|---|---|---|---|---|---|---|
| GeneracionRealEstimada | decimal | numero | 649270.0 | 0 | 275 | 0.0 | 23751910.0 | Generación real estimada a través del SCADA |
| GeneracionProgramadaRedespacho | decimal | numero | 506000.0 | 0 | 220 | 0.0 | 23801000.0 | Generación programada en el redespacho |
| CodigoPlanta | texto | texto | TPUY | 0 | 381 | 2QBW | ZPA5 | Código de la planta |
| TipoGeneracion | texto | texto | Solar | 0 | 5 | Cogenerador | Termica | Tipo de clasificación del recurso de generación |
| TipoClasificacion | texto | texto | Solar | 0 | 10 | AUTOGENERADOR | Termica | Clasificación del generador según la regulación actual |
| GeneracionProgramadaDespacho | decimal | numero | 506000.0 | 0 | 222 | 0.0 | 23801000.0 | Generación programada en el despacho económico |
| Fecha | fecha | texto | 2025-03-01 | 0 | 1 | 2025-03-01 | 2025-03-01 | Fecha de representación de la información |
| TipoDespachoRecurso | texto | texto | Despachado Centralmente | 0 | 2 | Despachado Centralmente | No Despachado Centralmente | Tipo de despacho del recurso |

## Que identifica la fila

Filas: 381. Filas duplicadas exactas: 0.
- Columnas unicas por si solas: CodigoPlanta

## Unidad

- `GProgRedespacho` (Generación programada redespacho unidad): kWh
- `GeneracionRealEstimada` (Generación real estimada): kWh
- `GProgDespacho` (Generación programada despacho unidad): kWh

## Valores de las columnas categoricas (tipo de serie y clasificaciones)

- `Fecha` (1 valores): 2025-03-01=381
- `TipoGeneracion` (5 valores): Hidraulica=159, Solar=137, Termica=71, Cogenerador=12, Eolica=2
- `TipoClasificacion` (10 valores): Hidraulica=117, Solar=71, GENERADOR DISTRIBUIDO=67, AUTOGENERADOR=50, Termica=42, COGENERADOR=12, FILO DE AGUA=10, CICLO COMBINADO=8, Eolica=2, AUTOGENERADOR PEQUEÑA ESCALA=2
- `TipoDespachoRecurso` (2 valores): No Despachado Centralmente=302, Despachado Centralmente=79

## Nulos, negativos y ceros

| Columna | Nulos | Negativos | Ceros | Filas |
|---|---|---|---|---|
| GeneracionRealEstimada | 0 | 0 | 80 | 381 |
| GeneracionProgramadaDespacho | 0 | 0 | 86 | 381 |
| GeneracionProgramadaRedespacho | 0 | 0 | 87 | 381 |

## Zona horaria

Sin hora en los datos (granularidad Diaria): la zona no aplica a esta fecha.

## Comparacion F01 vs F02 (D02)

Se compara `GeneracionRealEstimada` de F01 (kWh por dia y planta) con la suma de `Valor` de F02 en las 24 horas, por cada version.
Plantas solo en F01: 0; solo en F02: 4 (2XXR, 3AL6, 3AXV, 3HWK).

| Version F02 | Plantas F02 | Plantas en ambos | Coinciden (dif <= 1 kWh) | Dentro de 1 % | Difieren (> 1 kWh) | Plantas con horas != 24 |
|---|---|---|---|---|---|---|
| TX1 | 381 | 381 | 85 | 174 | 296 | 0 |
| TX2 | 385 | 381 | 85 | 172 | 296 | 0 |
| TX3 | 385 | 381 | 85 | 172 | 296 | 0 |
| TX4 | 385 | 381 | 85 | 172 | 296 | 0 |
| TXF | 385 | 381 | 85 | 172 | 296 | 0 |
| TXR | 385 | 381 | 85 | 172 | 296 | 0 |

Version TXF frente a F01, por `TipoGeneracion` (energia en kWh):

| TipoGeneracion | Plantas | Coinciden | Suma F01 | Suma F02 | Dif. % |
|---|---|---|---|---|---|
| Cogenerador | 12 | 0 | 2,836,680 | 2,878,174 | 1.46 |
| Eolica | 2 | 0 | 341,580 | 333,095 | -2.48 |
| Hidraulica | 159 | 35 | 179,199,450 | 178,780,172 | -0.23 |
| Solar | 137 | 12 | 13,067,690 | 13,025,282 | -0.32 |
| Termica | 71 | 38 | 23,744,300 | 23,778,719 | 0.14 |

Total del dia: F01 = 219,189,700 kWh, F02 (TXF) = 218,795,443 kWh (-0.18 %). Plantas con F01 = 0 y F02 != 0: 13; con F01 != 0 y F02 = 0: 5.
