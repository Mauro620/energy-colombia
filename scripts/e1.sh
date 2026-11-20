#!/usr/bin/env bash
# Entrega 1 de punta a punta: recrea energia_db, ejecuta sql/00 a 05 en orden y guarda la salida en evidencias/E1/.
# Equivale a `make e1` (make no esta instalado en todas las maquinas). Requiere .env o POSTGRES_* exportadas.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
export UID_GID="$(id -u):$(id -g)"
: "${POSTGRES_USER:?defina POSTGRES_USER}" "${POSTGRES_PASSWORD:?defina POSTGRES_PASSWORD}" "${POSTGRES_VERSION:?defina POSTGRES_VERSION}"

LOG="evidencias/E1/ejecucion_$(date +%Y-%m-%d_%H%M).log"
mkdir -p evidencias/E1
exec > >(tee "$LOG") 2>&1

psql_db() { docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" "$@"; }
correr() { echo; echo "=== $1"; local t0=$SECONDS; psql_db -d energia_db -f "/sql/$1"; echo "--- $1: $((SECONDS - t0)) s"; }

echo "# Entrega 1: ejecucion $(date -Is)"
docker compose up -d --wait db

echo "=== Recrear la base (parte de una base vacia)"
psql_db -d postgres -c "DROP DATABASE IF EXISTS energia_db WITH (FORCE)"
for f in sql/00_setup/*.sql; do echo "=== ${f#sql/}"; psql_db -d postgres -f "/sql/${f#sql/}"; done

echo "=== Aplanar data/raw a data/stage (Python solo extrae y aplana)"
docker compose run --rm -T tools python -m pipeline.transform.aplanar

for fase in 01_ddl 02_reglas 03_carga 04_consultas 05_pruebas; do
  for f in sql/$fase/*.sql; do correr "${f#sql/}"; done
done
echo; echo "# Fin: $(date -Is)"
