#!/usr/bin/env bash
# Arma entregables/E1/ desde el estado actual del repo: MER, un .sql por etapa (numerados en el orden de ejecucion) y el log de la ultima ejecucion.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=entregables/E1
mkdir -p "$OUT"
rm -f "$OUT"/[0-9][0-9]_*.sql
# Fuente del modelo y diccionario. Las imagenes y el .mmd viven solo en $OUT (se borraron de docs/modelo para no duplicar); fallar si faltan.
cp docs/modelo/modelo_er.dbml docs/modelo/diccionario.md "$OUT"/
for f in modelo_er.png modelo_er.svg modelo_er.mmd; do [ -f "$OUT/$f" ] || { echo "falta $OUT/$f"; exit 1; }; done

etapa() {  # etapa <salida> <encabezado> <archivos...>: concatena los .sql de una etapa con su encabezado
  local salida=$1 encabezado=$2; shift 2
  { printf -- '-- %s\n-- Generado por scripts/empaquetar_e1.sh. Ejecutar con: psql -v ON_ERROR_STOP=1 -U postgres -d <base> -f %s\n' "$encabezado" "$(basename "$salida")"
    for f in "$@"; do printf -- '\n-- ======================================================================\n-- %s\n-- ======================================================================\n' "$f"; cat "$f"; done; } > "$OUT/$salida"
}
etapa 01_setup.sql          "Setup: base energia_db, extensiones y esquemas. Conectarse a la base postgres." sql/00_setup/*.sql
etapa 02_tablas.sql         "DDL: tipos, catalogos, entidades, hechos, control y staging. Base energia_db." sql/01_ddl/*.sql
etapa 03_reglas.sql         "Reglas de integridad: CHECK, EXCLUDE y triggers. Base energia_db." sql/02_reglas/*.sql
etapa 04_vistas.sql         "Vistas del esquema analitica. Requiere la base cargada (sql/03_carga con data/stage)." sql/04_consultas/041_vistas.sql
etapa 05_consultas_having.sql  "Consultas GROUP BY + HAVING (Q01 a Q03). Requiere las vistas." sql/04_consultas/042_consultas_having.sql
etapa 06_consultas_ventana.sql "Consultas con funciones de ventana (Q04 a Q07). Requiere las vistas." sql/04_consultas/043_consultas_ventana.sql
etapa 07_consultas_joins.sql   "Consultas con JOIN: INNER, LEFT, FULL y por fecha (Q08 a Q11). Requiere las vistas." sql/04_consultas/044_consultas_joins.sql
etapa 08_pruebas_reglas.sql    "Bateria de pruebas de las reglas de integridad (todo con ROLLBACK)." sql/05_pruebas/051_pruebas_reglas.sql
etapa 09_pruebas_calidad.sql   "Pruebas de calidad de los datos cargados." sql/05_pruebas/052_pruebas_calidad.sql

ultimo=$(ls -1t evidencias/E1/ejecucion_*.log | head -1)
cp "$ultimo" "$OUT/ejecucion_log.txt"
idem=$(ls -1t evidencias/E1/idempotencia_*.log 2>/dev/null | head -1 || true)
[ -n "$idem" ] && cp "$idem" "$OUT/idempotencia_log.txt"
echo "entregables/E1: $(ls "$OUT" | wc -l) archivos; log = $ultimo"
