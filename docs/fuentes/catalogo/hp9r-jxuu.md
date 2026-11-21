# Catálogo Nacional de Estaciones del IDEAM (`hp9r-jxuu`)

_Generado por `pipeline/extract/socrata_metadata.py`. No editar a mano._

- **Portal:** https://www.datos.gov.co/d/hp9r-jxuu
- **Entidad publicadora:** Instituto de Hidrología, Meteorología y Estudios Ambientales - IDEAM, Bogotá D.C.
- **Tipo de activo:** dataset
- **Fecha de actualizacion:** 2026-11-19 09:27 UTC
- **Licencia:** Creative Commons Attribution \| Share Alike 4.0 International
- **Total de filas:** 57706
- **Descripcion:** Este dataset relaciona la información de las estaciones hidrometeorológicas de propiedad del IDEAM y de otras entidades: contiene nombre de la estación, código, tipo, categoría, localización, entre otros.  Los datos disponibles a través de este medio pueden ser libremente consumidos bajo las siguientes cláusulas: 1. Los datos a visualizar o descargar a continuación no han sido validados por el IDEAM. 2. Los datos aquí dispuestos son datos crudos instantáneos provenientes de los sensores de las estaciones automáticas de la red propia y/o producto de convenios interadministrativos con terceras entidades. 3. Los datos son puestos a disposición de la ciudadanía como mecanismo de transparencia y para proveer una herramienta de apoyo a la gestión del riesgo territorial y como datos abiertos en cumplimiento de la Ley 1712 de 2014. 4. Es posible que los datos aquí dispuestos tengan cierto retraso en el tiempo debido a las frecuencias de envío de datos de los sensores y los medios de transmisión utilizados. 5. Los datos presenten errores y/o inconsistencias estando incluso por fuera de los límites considerados normales, producto de fallas en los sensores de origen. 6. El posterior uso e interpretación que se le dé para cualquier finalidad queda bajo la exclusiva responsabilidad del portador de los datos. 7. Cualquier destino que se le dé a los datos exime al IDEAM de realizarles cualquier tipo de justificación o iniciarles proceso alguno de validación posterior, cuya fuente primaria deben ser los canales oficialmente dispuestos por la Entidad para el suministro de información oficial y validada. 8. Por las razones expuestas anteriormente los datos dispuestos no podrán ser utilizados como evidencia jurídica ante entes de control acerca de la ocurrencia o no de fenómenos hidroclimatológicos o de soporte a cualquier tipo de situación o evento ocurrido como consecuencia de estos.

## Columnas

| Nombre | Tipo | Descripcion |
|---|---|---|
| codigo (Codigo) | text | Corresponde al valor de identificación de la estación dentro del catálogo de estaciones |
| nombre (Nombre) | text | Corresponde a la identificación de la estación dentro del catálogo de estaciones, tambien lleva el codigo de la estacion |
| categoria (Categoria) | text | Indica la categoría de la estación de medición de acuerdo con su clase |
| tecnologia (Tecnologia) | text | Corresponde a los tipos de estaciones de medición: convencional, automática con telemetría, automática sin telemetría |
| estado (Estado) | text | Indica las condiciones de funcionamiento en las que actualmente se encuentra la estación de medición |
| departamento (Departamento) | text | Nombre del departamento donde se ubica la estación |
| municipio (Municipio) | text | Nombre del Municipio donde se localiza la estación |
| ubicaci_n (Ubicación) | location | Corresponde a la latitud y longitud en la cual se encuentra la estación. |
| altitud (Altitud) | number | Indica el valor de la altura sobre el nivel del mar de la estación de medición |
| longitud (LONGITUD) | number | Corresponde a la coordenada longitud en grados, minutos, segundos y dirección (O) Deben estar en sistema Magna Sirgas |
| latitud (LATITUD) | number | Corresponde a la coordenada latitud en grados, minutos, segundos  y dirección (N/S)  Deben estar en sistema Magna Sirgas |
| fecha_instalacion (Fecha_instalacion) | text | Corresponde a la fecha de instalación de la estación de monitoreo |
| fecha_suspension (Fecha_suspension) | text | Fecha en la cual la estación fue suspendida |
| area_operativa (Area Operativa) | text | Área operativa |
| corriente (Corriente) | text | Corriente sobre la cual está ubicada la estación |
| area_hidrografica (Area Hidrografica) | text | Area hidrografica sobre la cual está ubicada la estación |
| zona_hidrografica (Zona Hidrografica) | text | Zona hidrografica sobre la cual está ubicada la estación |
| subzona_hidrografica (Subzona hidrografica) | text | Subzona hidrográfica sobre la cual está ubicada la estación |
| entidad (Entidad) | text | Entidad propietaria de ls estación |
