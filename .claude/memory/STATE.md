# STATE — estado vivo (máx. 40 líneas)
_Actualizado: 2026-11-19_

## Objetivo actual
Fase 0 (descubrimiento de fuentes). Sin tablas hasta cerrar `docs/fuentes/hallazgos.md`. E1 vence 21-nov.

## En qué vamos
- Estructura, docker-compose, Makefile, pipeline extract/profiling listos. Postgres levanta y `001_base.sql` es idempotente.
- Metadata, muestras, perfiles y hallazgos generados en `docs/fuentes/`.
- XM (`vtmi-tusj`, `8gum-9k6v`) son entradas federadas a SIMEM: sin filas por Socrata.

## Siguiente paso
Decidir cómo se obtiene XM (API SIMEM) y cómo se acumula `57sv-p2fu` (ventana de un día).

## Pendientes
- Crear `.env.example` (bloqueado por regla deny; contenido en el chat de la sesión).
- Instalar `make` y venv (`sudo apt install make python3-venv python3-pip`).
- Llenar Unidad/Cruza/Decisión en la hoja Perfil_columnas (`--escribir-xlsx` opcional).

## Trampas conocidas
- `ubicaci_n.latitude` del catálogo IDEAM trae la longitud (invertido).
- `codigoestacion` de observaciones trae ceros a la izquierda.
- PyPI muy lento en esta máquina; verificación con imagen docker `energia-py` (debian + apt).
