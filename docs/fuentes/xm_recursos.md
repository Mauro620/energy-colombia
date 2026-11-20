# XM: listado de recursos con atributos (`ListadoRecursos`)

_Generado por `pipeline/extract/xm_listados.py`. No editar a mano._

- **Endpoint:** `POST https://servapibi.xm.com.co/lists` con `{"MetricId": "ListadoRecursos"}` (no hace falta fecha ni entidad). Crudo: `data/raw/xm_ListadoRecursos/`.
- **Como se identifico la metrica:** `ListadoMetricas` (`data/raw/xm_ListadoMetricas/`) tiene 193 entradas; `ListadoRecursos` aparece 2 veces: "plantas y unidades que tiene asociadas un agente por Agente" (entidad Agente); "Listado Recursos con atributos por Sistema" (entidad Sistema). Solo la de entidad Sistema trae atributos.
- **Filas (recursos):** 2521. Fecha de la foto: 2026-11-20.

## Columnas

| Columna | Ejemplo | Nulos | Distintos |
|---|---|---|---|
| Code | 2QBW | 0 | 2518 |
| Name | EL POPAL | 0 | 2519 |
| Type | HIDRAULICA | 0 | 6 |
| Disp | NO DESPACHADO CENTRALMENTE | 0 | 2 |
| RecType | NORMAL | 0 | 9 |
| CompanyCode | ISGG | 0 | 149 |
| EnerSource | AGUA | 0 | 12 |
| OperStartdate | 2014-03-31 | 0 | 735 |
| State | OPERACION | 0 | 3 |

## Llave del recurso

- `Code`: 2518 distintos en 2521 filas, 0 nulos, longitud de 4 a 4 caracteres -> NO unica.
- `Name`: 2519 distintos en 2521 filas.
- Filas con `Code` repetido: 6.

| Code | Name | Type | Disp | RecType | CompanyCode | EnerSource | OperStartdate | State |
|---|---|---|---|---|---|---|---|---|
| 5J8H | GRANJA SOLAR ASTURIAS | SOLAR | NO DESPACHADO CENTRALMENTE | NORMAL | GRCG | RAD SOLAR | 2026-10-30 | OPERACION |
| 5J8H | GRANJA SOLAR ASTURIAS | SOLAR | NO DESPACHADO CENTRALMENTE | NORMAL | GRCG | RAD SOLAR | 2026-10-30 | OPERACION |
| 5PUN | LA PAZ | SOLAR | NO DESPACHADO CENTRALMENTE | NORMAL | GRCG | RAD SOLAR | 2026-10-30 | OPERACION |
| 5PUN | LA PAZ | SOLAR | NO DESPACHADO CENTRALMENTE | NORMAL | GRCG | RAD SOLAR | 2026-10-30 | OPERACION |
| PRG1 | PROELECTRICA | TERMICA | DESPACHADO CENTRALMENTE | NORMAL | PRIG | GAS | 1993-07-01 | OPERACION |
| PRG1 | PROELECTRICA 1 | TERMICA | DESPACHADO CENTRALMENTE | NORMAL | PRIG | GAS | 1993-07-01 | OPERACION |

## Capacidad

**El listado NO trae capacidad** (ninguna de sus 9 columnas lo es). Metricas candidatas en `ListadoMetricas` (busqueda por `capacidad|ubicacion|municipio|departamento|coordenadas` en nombre y descripcion; no se llamaron):

| MetricId | Nombre | Entidad | Tipo | Unidad | MaxDays |
|---|---|---|---|---|---|
| RestSinAliv | Restricciones sin Alivios por Sistema | Sistema | HourlyEntities | COP | 31 |
| VoluUtilDiarEner | Volumen Útil diario Energía por Sistema | Sistema | DailyEntities | kWh | 31 |
| CapEfecNeta | Capacidad Efectiva Neta por Recurso | Recurso | DailyEntities | kW | 31 |
| CapaUtilDiarEner | Capacidad Útil Energía por Sistema | Sistema | DailyEntities | kWh | 31 |
| VoluUtilDiarEner | Volumen Útil diario Energía por Embalse | Embalse | DailyEntities | kWh | 31 |
| CapaUtilDiarEner | Capacidad Útil Energía por Embalse | Embalse | DailyEntities | kWh | 31 |
| VertMasa | Vertimientos Volumen por Embalse | Embalse | DailyEntities | m3 | 31 |
| VertEner | Vertimientos Energía por Embalse | Embalse | DailyEntities | kWh | 31 |
| VertEner | Vertimientos Energía por Sistema | Sistema | DailyEntities | kWh | 31 |
| CapaUtilDiarMasa | Capacidad Útil Volumen por Embalse | Embalse | DailyEntities | m3 | 31 |
| CapaUtilDiarMasa | Capacidad Útil Volumen por Sistema | Sistema | DailyEntities | m3 | 31 |
| CERE | CERE por Sistema | Sistema | MonthlyEntities | COP/kWh | 731 |
| CEE | CEE por Sistema | Sistema | MonthlyEntities | COP/kWh | 731 |

## Tecnologia

- `Type`: SOLAR=2222, HIDRAULICA=161, TERMICA=82, Solar=37, COGENERADOR=12, EOLICA=7. Variantes solo por mayusculas: ['Solar'] (`Solar`=37 vs `SOLAR`=2222).
- `EnerSource`: RAD SOLAR=2259, AGUA=161, GAS=44, CARBON=19, BAGAZO=14, VIENTO=7, BIOGAS=6, COMBUSTOLEO=4, ACPM=3, BIOMASA=2, GLP=1, JET-A1=1.
- `RecType`: AUTOG PEQ. ESCALA=1847, NORMAL=298, GEN. DISTRIBUIDA=279, AUTOGENERADOR=59, FILO DE AGUA=14, COGENERADOR=12, CICLO COMBINADO=10, AUTOG REMOTO=1, FILO AGUA ESPECIAL=1.
- `EnerSource` frente a `fuente` de UPME (`tq63-itzr`, 13 valores): coinciden 12 de 12 valores de XM; solo en XM: []; solo en UPME: ['OTROS'].

`Type` del listado frente a `TipoGeneracion` de F01 (plantas de F01 que cruzan por codigo):

| Type (listado, en mayusculas) \ TipoGeneracion (F01) | Cogenerador | Eolica | Hidraulica | Solar | Termica |
|---|---|---|---|---|---|
| COGENERADOR | 12 | 0 | 0 | 0 | 0 |
| EOLICA | 0 | 2 | 0 | 0 | 0 |
| HIDRAULICA | 0 | 0 | 158 | 0 | 0 |
| SOLAR | 0 | 0 | 0 | 136 | 0 |
| TERMICA | 0 | 0 | 0 | 0 | 69 |

## Agente

- `CompanyCode`: 149 agentes distintos, 0 nulos. Mayores: GNCC=516, SCEC=317, NEUC=282, ETTC=141, ENBC=129, BIAC=91, EPMC=88, EPSG=74.
- F02 trae `CodigoSICAgente` (92 agentes en el dia explorado): ver `simem_055A4D.md`.

## Ubicacion

**El listado NO trae ubicacion** (ni municipio, ni departamento, ni coordenadas). Ver las metricas candidatas arriba; ninguna de ellas es por municipio.

## Otros atributos

- `Disp`: NO DESPACHADO CENTRALMENTE=2417, DESPACHADO CENTRALMENTE=104.
- `State`: OPERACION=2100, PRUEBAS=223, Operacion=198 (variantes de mayusculas: `OPERACION` vs `Operacion`).
- `OperStartdate`: de 1925-01-01 a 2026-11-12; 0 nulos o no interpretables.

## Cruce de la llave con SIMEM (P07)

- E17D25 F01 (generacion diaria por planta), dia 2025-03-01: 376 de 381 `CodigoPlanta` existen en `Code` (98.7 %); tras `strip().upper()`: 376. No cruzan: 3IJF, 3KL4, 3RKN, 3RKP, 4SNT.
  - Recursos del listado presentes en F01: 376 de 2518 (14.9 %); el resto no genero ese dia o no esta en F01.
- 055A4D F02 (generacion horaria por planta), dia 2025-03-01: 379 de 385 `CodigoPlanta` existen en `Code` (98.4 %); tras `strip().upper()`: 379. No cruzan: 3AL6, 3IJF, 3KL4, 3RKN, 3RKP, 4SNT.
