# Producción de electricidad por fuente de combustible (`tq63-itzr`)

_Generado por `pipeline/extract/socrata_metadata.py`. No editar a mano._

- **Portal:** https://www.datos.gov.co/d/tq63-itzr
- **Entidad publicadora:** UPME
- **Tipo de activo:** dataset
- **Fecha de actualizacion:** 2026-08-25 16:44 UTC
- **Licencia:** Creative Commons Attribution 4.0 International
- **Total de filas:** 2786
- **Descripcion:** Información mensual sobre la producción de energía eléctrica en Colombia, desagregada por tipo de fuente de combustible. Incluye métricas de generación total, promedios, valores extremos y porcentaje de participación. La información es recopilada y procesada a partir de los datos operativos suministrados por XM y posteriormente analizada, modificada y adaptada técnicamente por la UPME.

## Columnas

| Nombre | Tipo | Descripcion |
|---|---|---|
| ano (Año) | number | Año de registro de la información. |
| mes (Mes) | number | Mes correspondiente a la medición de la generación. |
| fuente (Fuente) | text | Tipo de recurso o combustible utilizado para la generación de energía. |
| promedio_mensual_gwh (Promedio mensual GWh) | number | Promedio de energía generada en el mes expresado en Gigavatios hora. |
| maximo_gwh (Máximo GWh) | number | Valor máximo de energía generada en un solo día del mes (GWh). |
| minimo_gwh (Mínimo GWh) | number | Valor mínimo de energía generada en un solo día del mes (GWh). |
| generacion_total_gwh (Generación total GWh) | number | Suma total de energía generada durante todo el mes expresada en Gigavatios hora. |
| porcentaje_participacion (% Participación) | number | Porcentaje de aporte de la fuente respecto a la generación eléctrica total del mes. |
