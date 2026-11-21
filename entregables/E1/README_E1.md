# Entrega 1: modelado, ingesta y reglas (energia_db)

Sistema Energetico Colombiano con datos abiertos de XM, UPME e IDEAM. PostgreSQL 16. Evidencia: `modelo_er.png/.svg/.dbml/.mmd`, `diccionario.md`, los `.sql` numerados `01` a `09` en orden de ejecucion (setup, tablas, reglas, vistas, consultas HAVING / ventana / JOINs, pruebas de reglas y de calidad) y `ejecucion_log.txt`.

## Fuentes y periodos (D07-rev)

| Cod. | Fuente | Contenido | Periodo / filas |
|---|---|---|---|
| F01 | SIMEM `E17D25` (datos.gov.co `vtmi-tusj`) | Generacion diaria por planta: programada despacho, redespacho y real SCADA (kWh) | 2025-01-01 a 2026-10-31, 330 379 filas |
| F02 | SIMEM `055A4D` (`8gum-9k6v`) | Generacion horaria por planta, hasta 6 versiones de liquidacion por hora (kWh) | 2026-05-01 a 2026-10-31, 12 785 568 filas -> 2 695 786 horas vigentes |
| F07, F11, F10 | API XM | Listado de recursos (2 521), de agentes (718) y capacidad efectiva neta diaria (925 228 dias -> 2 568 rangos) | foto 2026-11-20; capacidad 2025-01 a 2026-10 |
| F03 | UPME `tq63-itzr` | Generacion mensual por fuente (GWh) | 2000-01 a 2026-08, 2 786 filas |
| F04, F05 | IDEAM `hp9r-jxuu`, `57sv-p2fu` | Catalogo de estaciones (57 706 filas = 9 935 estaciones) y observaciones | observaciones: ~12 h acumuladas (2026-11-19), 156 981 filas |
| F08 | DANE DIVIPOLA `gdxc-w37w`, `vcjz-niiq` | 1 122 municipios y 33 departamentos | foto 2026-11-20 |

## Decisiones principales (`docs/decisiones/0002-modelo-e1.md`, hoja Decisiones del xlsx)

- **D02-rev:** dos hechos, `generacion_diaria_planta` (F01) y `generacion_horaria_planta` (F02, una fila vigente por planta y hora). F01 y F02 son mediciones distintas (SCADA vs liquidacion): solo 85 de 381 plantas coinciden. Nunca se suman.
- **D13:** `capacidad_planta` por rangos de vigencia con `EXCLUDE`. **D14:** sin relacion planta-estacion. **D05:** DIVIPOLA con codigo DANE como PK. **D08:** centinelas fuera. **D09:** UPME `periodo date`, porcentaje en vista.
- **Supuesto S-01 (validar):** orden de versiones TX1 < TX2 < TXR < TXF < TX3 < TX4; ningun documento lo publica. Se cambia en `energia.version_liquidacion.orden`.

## Limitaciones

1. No hay ubicacion de plantas: clima y generacion se relacionan solo por tiempo (D14). La consulta Q11 devuelve 0 filas hoy porque las observaciones cubren 1 dia y la generacion diaria llega al 2026-10-31.
2. El cruce de estaciones con DIVIPOLA por nombre es del 89,5 %: Bogota, Cali y Cucuta no cruzan, y con ellas se pierde el 39,3 % de las observaciones (cuarentena DQ15).
3. Plantas fuera del listado de recursos (134 en F01, 40 en F02) y recursos con capacidad que no estan en el listado van a cuarentena (RN17).
4. Rangos de sensores provisionales (S-02): salen de ~12 h de datos.
5. F02 cubre 6 meses; se amplia en E3.

## Como ejecutar (desde cero)

```bash
cp .env.example .env        # POSTGRES_VERSION, POSTGRES_USER, POSTGRES_PASSWORD
make e1                     # o: bash scripts/e1.sh   (~14 min; recrea energia_db y guarda evidencias/E1/ejecucion_<fecha>.log)
bash scripts/xlsx_e1.sh     # llena las hojas del modelo del xlsx
bash scripts/empaquetar_e1.sh
```
Requiere `data/raw/` (se regenera con los scripts de `pipeline/extract/`; no se versiona). Los scripts SQL son numerados, idempotentes y corren con `psql -v ON_ERROR_STOP=1`.

## Resultados de la ejecucion desde cero

| Lote (fuente) | Leidas | Insertadas | Omitidas | Rechazadas |
|---|---|---|---|---|
| divipola departamentos / municipios | 33 / 1 122 | 33 / 1 122 | 0 | 0 |
| xm_ListadoAgentes | 718 | 713 | 5 | 0 |
| xm_ListadoRecursos | 2 521 | 2 518 | 3 | 0 |
| UPME | 2 786 | 2 786 | 0 | 0 |
| xm_CapEfecNeta (dias) | 925 228 | 921 213 | 0 | 4 015 (RN17) |
| simem_E17D25 | 330 379 | 323 995 | 749 | 5 635 (RN05 3 617, RN17 2 018) |
| simem_055A4D | 12 785 568 | 2 695 786 | 9 856 680 | 233 102 (RN17 217 440, RN10 15 662) |
| catalogo IDEAM | 57 706 | 8 897 | 42 639 | 6 170 (DQ14 6 146, RN12 24) |
| observaciones IDEAM | 156 981 | 93 667 | 0 | 63 314 (DQ15 61 735, DQ09 1 186, DQ08 393) |

Pruebas: **55 casos de reglas, 55 PASS, 0 FAIL** (23514, 23503, 23505, 23P01, P0001, 23502, 22P02 y casos positivos; todo con ROLLBACK). Calidad: conteos de staging = insertadas + actualizadas + omitidas + rechazadas en los 10 lotes; 0 duplicados por clave de negocio; 0 huerfanas; 0 vigencias solapadas.
