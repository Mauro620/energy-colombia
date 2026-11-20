# Perfil de Producción de electricidad por fuente de combustible (`tq63-itzr`)

_Generado por `pipeline/profiling/perfilar.py`. No editar a mano._

- Filas en la muestra: 2786 de 2786 (muestra completa: los duplicados y unicidades valen para todo el dataset)
- Filas duplicadas exactas en la muestra: 0

## Columnas

| Columna | Tipo origen | Tipo inferido | Ejemplo | % nulos | Distintos | Minimo | Maximo | Identifica fila |
|---|---|---|---|---|---|---|---|---|
| ano | number | entero | 2000 | 0.0% | 27 | 2000 | 2026 | - |
| mes | number | entero | 1 | 0.0% | 12 | 1 | 12 | - |
| fuente | text | texto | ACPM | 0.0% | 13 | ACPM | VIENTO | - |
| promedio_mensual_gwh | number | decimal | 1.577589611111111 | 0.0% | 2785 | 0.000000010 | 195.5086514819355 | - |
| maximo_gwh | number | decimal | 2.683876 | 0.0% | 2784 | 0.000000010 | 215.65083914 | - |
| minimo_gwh | number | decimal | 0.5307066 | 0.0% | 2740 | 0.000000010 | 170.09654516 | - |
| generacion_total_gwh | number | decimal | 14.1983065 | 0.0% | 2785 | 0.000000010 | 6060.76819594 | - |
| porcentaje_participacion | number | decimal | 0.426629829719028 | 0.0% | 2786 | 1.759059132193384E-10 | 91.0110309084956 | - |

## Combinaciones candidatas (2-3 columnas sin nulos ni duplicados en la muestra)

- ano, fuente, mes
