#!/usr/bin/env bash
# INSERT/UPDATE/DELETE en control.replica_demo (RDS) y medicion de cuanto tarda en verse en local (energia_replica).
# La latencia incluye el costo de cada consulta de sondeo (docker exec, ~100 ms): es una cota superior.
. "$(dirname "$0")/_comun.sh"
cargar_rds

RDB=energia_replica
ID="$(date +%s)"

ms() { echo $(( ($(date +%s%N) - $1) / 1000000 )); }

# $1 etiqueta, $2 SQL en RDS, $3 consulta local que devuelve 't' cuando el cambio ya llego
medir() {
  rds_psql -q -c "$2"
  local t0; t0="$(date +%s%N)"
  until [ "$(LOCAL_DB=$RDB local_psql -qAt -c "$3")" = t ]; do
    [ "$(ms "$t0")" -lt 60000 ] || { echo "$1: no llego en 60 s" >&2; exit 1; }
    sleep 0.05
  done
  echo "$1: visible en local tras $(ms "$t0") ms"
}

echo "=== INSERT"
medir INSERT "INSERT INTO control.replica_demo (id, texto) VALUES ($ID, 'insertado en RDS')" \
  "SELECT count(*) = 1 FROM control.replica_demo WHERE id = $ID"
LOCAL_DB=$RDB local_psql -c "SELECT id, texto, actualizado_en FROM control.replica_demo WHERE id = $ID"

echo "=== UPDATE"
medir UPDATE "UPDATE control.replica_demo SET texto = 'actualizado en RDS', actualizado_en = now() WHERE id = $ID" \
  "SELECT count(*) = 1 FROM control.replica_demo WHERE id = $ID AND texto = 'actualizado en RDS'"
LOCAL_DB=$RDB local_psql -c "SELECT id, texto, actualizado_en FROM control.replica_demo WHERE id = $ID"

echo "=== DELETE"
medir DELETE "DELETE FROM control.replica_demo WHERE id = $ID" \
  "SELECT count(*) = 0 FROM control.replica_demo WHERE id = $ID"
LOCAL_DB=$RDB local_psql -c "SELECT count(*) AS filas_con_ese_id FROM control.replica_demo WHERE id = $ID"

echo "=== Local: pg_stat_subscription"
LOCAL_DB=$RDB local_psql -c "SELECT subname, pid, received_lsn, last_msg_send_time, last_msg_receipt_time, latest_end_lsn, latest_end_time FROM pg_stat_subscription"
echo "=== RDS: pg_replication_slots"
rds_psql -c "SELECT slot_name, plugin, slot_type, active, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots"
