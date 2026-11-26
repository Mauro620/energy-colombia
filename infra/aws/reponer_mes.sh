#!/usr/bin/env bash
# Repone en RDS un mes de generacion_diaria_planta desde la base local (tras el DELETE de pitr.sh).
# Uso: MES=2026-09-01 bash infra/aws/reponer_mes.sh   (por defecto 2026-09-01). Aborta si RDS ya tiene filas de ese mes.
. "$(dirname "$0")/_comun.sh"
cargar_rds
docker compose up -d --wait db

MES="${MES:-2026-09-01}"
RANGO="fecha >= '$MES'::date AND fecha < '$MES'::date + interval '1 month'"
COLS="planta_id, fecha, programada_despacho_kwh, programada_redespacho_kwh, real_estimada_kwh"
RESUMEN="SELECT count(*), coalesce(sum(real_estimada_kwh), 0) FROM energia.generacion_diaria_planta WHERE $RANGO"

en_rds="$(rds_psql -qAt -F ' | ' -c "$RESUMEN")"
[ "${en_rds%% |*}" = 0 ] || { echo "RDS ya tiene filas de $MES ($en_rds): no se repone." >&2; exit 1; }
local_antes="$(local_psql -qAt -F ' | ' -c "$RESUMEN")"
echo "mes $MES: local = $local_antes | RDS = $en_rds"

echo "=== Copia local -> RDS"
local_psql -qAt -c "\\copy (SELECT $COLS FROM energia.generacion_diaria_planta WHERE $RANGO) TO STDOUT" \
  | rds_psql -q -c "\\copy energia.generacion_diaria_planta ($COLS) FROM STDIN"

en_rds="$(rds_psql -qAt -F ' | ' -c "$RESUMEN")"
echo "mes $MES en RDS tras reponer: $en_rds (esperado: $local_antes)"
[ "$en_rds" = "$local_antes" ] && echo "REPOSICION: PASS" || { echo "REPOSICION: FAIL"; exit 1; }
