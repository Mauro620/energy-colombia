#!/usr/bin/env bash
# Borra la suscripcion local y el slot de replicacion en RDS (un slot huerfano retiene WAL y llena el disco).
. "$(dirname "$0")/_comun.sh"
cargar_rds
docker compose up -d --wait db

SUB=sub_energia; RDB=energia_replica
existe="$(LOCAL_DB=postgres local_psql -qAt -c "SELECT count(*) FROM pg_database WHERE datname = '$RDB'")"
if [ "$existe" = 1 ]; then
  n="$(LOCAL_DB=$RDB local_psql -qAt -c "SELECT count(*) FROM pg_subscription s JOIN pg_database d ON d.oid = s.subdbid WHERE d.datname = '$RDB' AND s.subname = '$SUB'")"
  if [ "$n" = 1 ]; then
    LOCAL_DB=$RDB local_psql -q -c "ALTER SUBSCRIPTION $SUB DISABLE"
    LOCAL_DB=$RDB local_psql -q -c "DROP SUBSCRIPTION $SUB" # tambien borra el slot en RDS si hay conexion
    echo "suscripcion $SUB borrada"
  else
    echo "no hay suscripcion $SUB"
  fi
fi

echo "=== Slots restantes en RDS"
rds_psql -qAt -c "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name = '$SUB' AND NOT active"
rds_psql -c "SELECT slot_name, plugin, slot_type, active FROM pg_replication_slots"
