# Sistema Energetico Colombiano: PostgreSQL local + AWS RDS

Proyecto final de Administracion de Bases de Datos. Datos abiertos oficiales de XM, UPME e IDEAM (portal datos.gov.co y SIMEM).

## Fase actual: 0, descubrimiento de fuentes

El modelo de datos **todavia no esta definido**. Esta fase descarga metadata y muestras, las perfila y responde las preguntas P01-P16 de `docs/Integridad_Restricciones_Energia.xlsx` (hoja `Preguntas_fuentes`). Ver `docs/decisiones/0001-fase-descubrimiento.md`.

Salidas: `docs/fuentes/` (una ficha `<id>.md` y un `perfil_<id>.md` por dataset, `perfil_columnas.csv`, `hallazgos.md`).

## Entorno

Requisitos: Docker con Compose, `make`, Python 3.11+.

```bash
cp .env.example .env            # editar POSTGRES_PASSWORD
make up                         # PostgreSQL (version de POSTGRES_VERSION) con volumen persistente
make psql                       # consola en energia_db

make sample                     # metadata + muestras -> data/raw/ (no versionado) y data/sample/*.csv
make profile                    # perfiles + hallazgos -> docs/fuentes/
make down
```

Python corre dentro del contenedor `tools` (`pipeline/Dockerfile`): no hace falta pip ni venv local. Sin `make`, usa el equivalente:
`UID_GID=$(id -u):$(id -g) docker compose run --rm tools python -m pipeline.extract.socrata_metadata` (idem `socrata_sample`, `profiling.perfilar`, `profiling.hallazgos`).

`sql/00_setup/001_base.sql` se ejecuta solo al crear el volumen. Para repetirlo: `make down && docker volume rm <proyecto>_pgdata && make up`.

## Extraccion de XM e IDEAM

| Comando (dentro del contenedor `tools`) | Que hace |
|---|---|
| `python -m pipeline.extract.simem_explorar` | Descubre el datasetId de F01/F02, extrae 2025-03-01 y escribe `docs/fuentes/simem_<id>.md` |
| `python -m pipeline.extract.xm_listados` | Guarda `ListadoMetricas` y `ListadoRecursos` y escribe `docs/fuentes/xm_recursos.md` |
| `python -m pipeline.extract.simem_backfill --desde 2025-01-01 --hasta 2025-01-31` | Backfill de F01 en ventanas de 30 dias; reanudable |
| `python -m pipeline.extract.ideam_observaciones` | Descarga completa de `57sv-p2fu` y detecta huecos (DQ12) |

Todo se guarda con `pipeline/common_raw.py` en `data/raw/<fuente>/<fecha UTC de extraccion>/<inicio>_<fin>.json.gz` mas `manifest.jsonl` (url, parametros, hora, filas, bytes, sha256, estado). `data/raw` es inmutable: si el archivo existe, se omite y se registra.

### Acumulacion de observaciones IDEAM (GitHub Actions)

`.github/workflows/ideam_observaciones.yml` corre cada 3 h y a demanda (Actions > ideam_observaciones > Run workflow). Cada corrida sube dos artefactos con 90 dias de retencion: `ideam-datos-<run_id>` (el `.json.gz`) e `ideam-manifest` (manifiesto acumulado, que la siguiente corrida descarga para comparar). Si hay un hueco, el job falla en rojo y los artefactos se suben igual.

Descargar con la CLI de GitHub (`gh`):

```bash
gh run list --workflow ideam_observaciones.yml --limit 20          # ver corridas
gh run download <run_id> -n ideam-datos-<run_id> -D data/raw/ideam_observaciones   # un lote
gh run download <run_id> -n ideam-manifest -D data/raw/ideam_observaciones         # manifiesto
```

Tambien desde la web: Actions > la corrida > seccion Artifacts. Las fechas del manifiesto estan en hora de Colombia (como la fuente); `extraido_en` esta en UTC.

## Mapa de entregas

| Entrega | Fecha | Contenido |
|---|---|---|
| E1 | 21-nov | Modelado + ingesta + reglas |
| E2 | 28-nov | AWS RDS + sincronizacion |
| E3 | 5-dic | RBAC + monitoreo + tuning |

## Estructura

```
docs/{fuentes,decisiones,modelo,informes}   sql/00_setup ... 08_tuning (numerados, idempotentes)
pipeline/{extract,profiling,transform,load,quality}   infra/aws
data/raw (ignorado)  data/sample (versionado)   evidencias/{E1,E2,E3}
```

Contribuir: ver `CONTRIBUTING.md`.
