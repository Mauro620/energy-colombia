#!/usr/bin/env bash
# Un solo comando desde un clon limpio: crea .env si falta, construye la imagen de Python, descarga data/raw y corre la Entrega 1.
# Uso (WSL2 o Linux con Docker): bash scripts/desde_cero.sh
# Es reanudable: data/raw es inmutable y las ventanas ya descargadas se omiten.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null || { echo "docker no esta disponible en esta terminal (en WSL: Docker Desktop > Settings > Resources > WSL integration)"; exit 1; }
export UID_GID="$(id -u):$(id -g)"

if [ ! -f .env ]; then
  # Solo local (Postgres escucha en 127.0.0.1); clave aleatoria para no repetir una por defecto
  printf 'POSTGRES_VERSION=16\nPOSTGRES_USER=postgres\nPOSTGRES_PASSWORD=%s\n' "$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)" > .env
  echo ".env creado"
fi

py() { docker compose run --rm -T tools python -m "$@"; }
# Las ventanas fallidas quedan pendientes en el manifiesto: se reintenta hasta 3 veces
reintentar() { for _ in 1 2 3; do py "$@" && return 0; done; echo "FALLO tras 3 intentos: $*"; return 1; }

docker compose build tools
for m in socrata_full xm_listados xm_agentes xm_capacidad divipola ideam_observaciones; do reintentar pipeline.extract.$m; done
reintentar pipeline.extract.simem_backfill
reintentar pipeline.extract.simem_backfill --dataset 055A4D --desde 2026-05-01

bash scripts/e1.sh
