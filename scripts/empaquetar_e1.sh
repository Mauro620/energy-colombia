#!/usr/bin/env bash
# Arma entregables/E1/ desde el estado actual del repo (MER, scripts concatenados en orden y log de la ultima ejecucion).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=entregables/E1
mkdir -p "$OUT"
cp docs/modelo/modelo_er.png docs/modelo/modelo_er.svg docs/modelo/modelo_er.dbml docs/modelo/modelo_er.mmd docs/modelo/diccionario.md "$OUT"/

concatenar() {  # concatenar <salida> <encabezado> <archivos...>
  local salida=$1 encabezado=$2; shift 2
  { printf -- '-- %s\n-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f %s\n\n' "$encabezado" "$(basename "$salida")"
    for f in "$@"; do printf -- '\n-- ======================================================================\n-- %s\n-- ======================================================================\n' "$f"; cat "$f"; done; } > "$salida"
}
concatenar "$OUT/01_ddl_energia.sql" "Entrega 1: setup + DDL + reglas (sql/00_setup, 01_ddl y 02_reglas). Parte de una base vacia; es idempotente." \
  sql/00_setup/*.sql sql/01_ddl/*.sql sql/02_reglas/*.sql
concatenar "$OUT/02_consultas_y_pruebas.sql" "Entrega 1: vistas, consultas y bateria de pruebas (sql/04_consultas y 05_pruebas). Requiere la base cargada (sql/03_carga con data/stage)." \
  sql/04_consultas/*.sql sql/05_pruebas/*.sql
ultimo=$(ls -1t evidencias/E1/ejecucion_*.log | head -1)
cp "$ultimo" "$OUT/ejecucion_log.txt"
idem=$(ls -1t evidencias/E1/idempotencia_*.log 2>/dev/null | head -1 || true)
[ -n "$idem" ] && cp "$idem" "$OUT/idempotencia_log.txt"
echo "entregables/E1: $(ls "$OUT" | wc -l) archivos; log = $ultimo"
