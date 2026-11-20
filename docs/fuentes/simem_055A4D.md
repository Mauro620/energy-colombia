# SIMEM `055A4D`: Generación real

_Generado por `pipeline/extract/simem_explorar.py`. No editar a mano._

- **Origen:** Socrata `8gum-9k6v` (entrada federada) -> https://www.simem.co/datadetail/055a4d5f-3616-45e3-9bcd-1d3e3a4a47bd
- **Hipotesis del datasetId** (primeros 6 caracteres del uuid, en mayusculas = `055A4D`): CONFIRMADA: la API devuelve `idDataset = 055A4D` y el mismo nombre que Socrata.
- **Endpoint:** `GET https://www.simem.co/backend-files/api/PublicData?datasetId=&startDate=&endDate=` (fecha ISO, `endDate` inclusiva: 2 dias dan el doble de filas).
- **Dia extraido:** 2025-03-01 -> 55344 filas. Periodicidad Diaria, granularidad Horaria, ultima actualizacion 2026-11-19 04:38:35.
- **Descripcion:** Generación real de cada una de las plantas, en kWh.
- **Columna de fecha del filtro (`filterDate`):** FechaHora

## Mayusculas de los parametros (prueba hecha con el dataset mas liviano)

- datasetId/startDate/endDate (camelCase): success=True, 381 filas
- datasetid/startdate/enddate (minusculas): success=True, 381 filas
- DatasetId/StartDate/EndDate (PascalCase): success=True, 381 filas
- datasetId en minusculas (valor): success=True, 381 filas

## Columnas

| Columna | Tipo (API) | Tipo en el JSON | Ejemplo | Nulos | Distintos | Minimo | Maximo | Descripcion (API) |
|---|---|---|---|---|---|---|---|---|
| CodigoVariable | texto | texto | GReal | 0 | 1 | GReal | GReal | Código de la variable |
| Valor | decimal | numero | 0.0 | 0 | 5052 | 0.0 | 1083514.19 | Valor de la variable (escala de 4 cifras) |
| CodigoPlanta | texto | texto | SJM1 | 0 | 385 | 2QBW | ZPA5 | Código de la planta |
| UnidadMedida | texto | texto | kWh | 0 | 1 | kWh | kWh | Unidad de medida en la que se encuentra la variable |
| CodigoSICAgente | texto | texto | GPEG | 0 | 92 | AAGG | XFRG | Código del agente asignado por el ASIC |
| Version | texto | texto | TX3 | 0 | 6 | TX1 | TXR | Versión de la liquidación |
| FechaHora | fecha hora | texto | 2025-03-01 12:00:00 | 0 | 24 | 2025-03-01 00:00:00 | 2025-03-01 23:00:00 | Fecha y hora de representación del dato |
| CodigoDuracion | texto | texto | PT1H | 0 | 1 | PT1H | PT1H | Código de duración de la variable en formato ISO8601 |

## Que identifica la fila

Filas: 55344. Filas duplicadas exactas: 0.
- Combinacion sin duplicados: (CodigoPlanta, FechaHora, Version); duplicados = 0

## Unidad

- `GReal` (Generación real): kWh
- Columna `UnidadMedida` en el dia: {'kWh': 55344}

## Valores de las columnas categoricas (tipo de serie y clasificaciones)

- `CodigoVariable` (1 valores): GReal=55344
- `CodigoDuracion` (1 valores): PT1H=55344
- `UnidadMedida` (1 valores): kWh=55344
- `Version` (6 valores): TX3=9240, TX4=9240, TXF=9240, TXR=9240, TX2=9240, TX1=9144

## Nulos, negativos y ceros

| Columna | Nulos | Negativos | Ceros | Filas |
|---|---|---|---|---|
| Valor | 0 | 0 | 22660 | 55344 |

## Versiones de la liquidacion

`Version` toma 6 valores: TX3=9240, TX4=9240, TXF=9240, TXR=9240, TX2=9240, TX1=9144.
Cada (CodigoPlanta, FechaHora) aparece 5-6 veces (una por version): 44 de 9240 puntos tienen valores distintos entre versiones.

## Zona horaria

Plantas solares (segun F01 `TipoGeneracion = Solar`): 137; presentes en F02: 137.
Horas distintas en `FechaHora`: 24 (de 0 a 23). Hora de maxima generacion solar: 11:00.

| Hora en FechaHora | 05 | 06 | 07 | 08 | 09 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MWh solar | 0 | 67 | 526 | 1,060 | 1,390 | 1,560 | 1,601 | 1,468 | 1,470 | 1,531 | 1,254 | 879 | 219 | 1 | 0 |

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
