# Perfil de Datos de Estaciones de IDEAM y de Terceros (`57sv-p2fu`)

_Generado por `pipeline/profiling/perfilar.py`. No editar a mano._

- Filas en la muestra: 5000 de 156274 (muestra parcial, ordenada por `:id`: unicidades observadas no se confirman en origen)
- Filas duplicadas exactas en la muestra: 0

## Columnas

| Columna | Tipo origen | Tipo inferido | Ejemplo | % nulos | Distintos | Minimo | Maximo | Identifica fila |
|---|---|---|---|---|---|---|---|---|
| codigoestacion | text | entero | 0021208480 | 0.0% | 540 | 0011027030 | 5311500121 | - |
| codigosensor | text | entero | 0247 | 0.0% | 18 | 0027 | 0260 | - |
| fechaobservacion | calendar_date | timestamp | 2026-11-19T10:11:00.000 | 0.0% | 146 | 2026-11-19T10:11:00.000 | 2026-11-19T12:36:00.000 | - |
| valorobservado | number | decimal | 54.46 | 0.0% | 1711 | -9998 | 1011.3 | - |
| nombreestacion | text | texto | KENNEDY - AUT [21208480] | 0.0% | 540 | ABRIAQUÍ - AUT [1111500036] | ZULUAGA AUT [21065040] | - |
| departamento | text | texto | Bogotá | 0.0% | 33 | Amazonas | Vichada | - |
| municipio | text | texto | Bogotá, D.C | 0.0% | 349 | Abejorral | Zona Bananera | - |
| zonahidrografica | text | texto | Alto Magdalena | 0.0% | 31 | Alto Magdalena | Vaupes | - |
| latitud | number | decimal | 4.61104201 | 0.0% | 539 | -4.199509 | 13.3595 | - |
| longitud | number | decimal | -74.178333 | 0.0% | 538 | -81.701117 | -67.91911111 | - |
| descripcionsensor | text | texto | Humedad relativa del suelo a 50 cm horaria | 0.3% | 17 | Dirección del viento cada 10 minutos | Velocidad del viento cada 10 minutos | - |
| unidadmedida | text | texto | % | 0.3% | 7 | % | °C | - |
| entidad | text | texto | EMPRESA DE ACUEDUCTO Y ALCANTARILLADO DE BOGOTÁ E.S.P | 0.0% | 10 | CORPORACION AUTONOMA REGIONAL DE CUNDINAMARCA | PARQUES NACIONALES NATURALES | - |

## Combinaciones candidatas (2-3 columnas sin nulos ni duplicados en la muestra)

- codigoestacion, fechaobservacion, codigosensor
- nombreestacion, fechaobservacion, codigosensor
