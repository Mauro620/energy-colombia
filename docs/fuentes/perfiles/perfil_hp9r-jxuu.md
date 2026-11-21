# Perfil de Catálogo Nacional de Estaciones del IDEAM (`hp9r-jxuu`)

_Generado por `pipeline/profiling/perfilar.py`. No editar a mano._

- Filas en la muestra: 5000 de 57706 (muestra parcial, ordenada por `:id`: unicidades observadas no se confirman en origen)
- Filas duplicadas exactas en la muestra: 0

## Columnas

| Columna | Tipo origen | Tipo inferido | Ejemplo | % nulos | Distintos | Minimo | Maximo | Identifica fila |
|---|---|---|---|---|---|---|---|---|
| codigo | text | entero | 2615700040 | 0.0% | 5000 | 0011010010 | 5311700154 | candidata |
| nombre | text | texto | AGUAS DE MANIZALES - AUT  [2615700040] | 0.0% | 5000 | ABRIAQUÍ - AUT [1111500036] | ÁFRICA SUPERIOR [21245060] | candidata |
| categoria | text | texto | Limnigráfica | 0.0% | 14 | Agrometeorológica | Sinóptica Secundaria | - |
| tecnologia | text | texto | Automática con Telemetría | 0.0% | 4 | Automática con Telemetría | Convencional | - |
| estado | text | texto | Activa | 0.0% | 3 | Activa | Suspendida | - |
| departamento | text | texto | Caldas | 0.0% | 33 | Amazonas | Vichada | - |
| municipio | text | texto | Manizales | 0.0% | 868 | Abejorral | Íquira | - |
| ubicaci_n | location | texto | {"human_address": "{\"address\": \"\", \"city\": \"\", \"sta | 0.0% | 4728 | {"human_address": "{\"address\": \"\", \"city\": \"\", \"sta | {"human_address": "{\"address\": \"\", \"city\": \"\", \"sta | - |
| altitud | number | entero | 1659 | 0.0% | 1717 | 0 | 5072 | - |
| longitud | number | decimal | -75.490305556 | 0.0% | 2882 | -83.05619444 | -67.45 | - |
| latitud | number | decimal | 5.089916667 | 0.0% | 3074 | -4.283333333 | 13.383408 | - |
| fecha_instalacion | text | texto | 04/07/2018 | 1.3% | 1539 | 01/01/2001 | 31/12/2017 | - |
| area_operativa | text | texto | Area Operativa 09 - Cauca-Valle-Caldas | 0.0% | 11 | Area Operativa 01 - Antioquia-Chocó | Area Operativa 11 - Cundinamarca-Amazonas | - |
| corriente | text | texto | QUEBRADA EL GUAMO | 66.9% | 799 | AGUACLARA | ZULIA | - |
| area_hidrografica | text | texto | Magdalena Cauca | 0.0% | 5 | Amazonas | Pacifico | - |
| zona_hidrografica | text | texto | Cauca | 0.0% | 37 | Alto Magdalena | Yarí | - |
| subzona_hidrografica | text | texto | Río Chinchiná | 0.0% | 239 | Alto Atrato | San Andres | - |
| entidad | text | texto | CORPORACIÓN AUTÓNOMA REGIONAL DE CALDAS | 0.0% | 73 | ACUEDUCTO METROPOLITANO DE BUCARAMANGA | ÁREA METROPOLITANA DEL VALLE DE ABURRÁ | - |
| fecha_suspension | text | texto | 13/06/2025 | 62.9% | 714 | 01/01/2017 | 31/07/1998 | - |

## Combinaciones candidatas (2-3 columnas sin nulos ni duplicados en la muestra)

- ninguna encontrada
