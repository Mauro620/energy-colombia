#!/usr/bin/env bash
# Replicacion logica RDS (publicador) -> PostgreSQL local (suscriptor, base energia_replica).
# El suscriptor inicia la conexion: RDS no necesita alcanzar la maquina local.
# Publica el esquema energia completo y control.replica_demo (tabla de control de demo_replica.sh).
. "$(dirname "$0")/_comun.sh"
cargar_rds
docker compose up -d --wait db

PUB=pub_energia; SUB=sub_energia; RDB=energia_replica
RPW="$(openssl rand -hex 16)" # contrasena del replicador: solo vive en el catalogo pg_subscription local

echo "=== RDS: wal_level"
wal="$(rds_psql -qAt -c "SHOW wal_level")"
[ "$wal" = logical ] || { echo "wal_level=$wal (se esperaba logical): revise rds.logical_replication y reinicie la instancia." >&2; exit 1; }

echo "=== RDS: tabla de control y verificacion de claves primarias"
rds_psql -q <<'SQL'
CREATE TABLE IF NOT EXISTS control.replica_demo (
  id             integer     PRIMARY KEY,
  texto          text        NOT NULL,
  actualizado_en timestamptz NOT NULL DEFAULT now()
);
SQL
sin_pk="$(rds_psql -qAt <<'SQL'
SELECT coalesce(string_agg(format('%I.%I', n.nspname, c.relname), ', '), '')
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND (n.nspname = 'energia' OR (n.nspname = 'control' AND c.relname = 'replica_demo'))
  AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisprimary);
SQL
)"
[ -z "$sin_pk" ] || { echo "Tablas a publicar sin PK (UPDATE/DELETE no se replicarian): $sin_pk" >&2; exit 1; }
echo "todas las tablas publicadas tienen PK"

particionadas="$(rds_psql -qAt -c "SELECT EXISTS (SELECT 1 FROM pg_partitioned_table p JOIN pg_class c ON c.oid = p.partrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'energia')")"
pvr=false; [ "$particionadas" = t ] && pvr=true

echo "=== RDS: usuario replicador y publicacion (publish_via_partition_root=$pvr)"
rds_psql -q -v pvr="$pvr" <<SQL
SELECT 'CREATE ROLE replicador LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicador') \gexec
ALTER ROLE replicador WITH PASSWORD '$RPW';
GRANT rds_replication TO replicador;
GRANT USAGE ON SCHEMA energia, control TO replicador;
GRANT SELECT ON ALL TABLES IN SCHEMA energia TO replicador;
GRANT SELECT ON control.replica_demo TO replicador;
SELECT format('CREATE PUBLICATION $PUB FOR TABLES IN SCHEMA energia, TABLE control.replica_demo WITH (publish_via_partition_root = %s)', :'pvr')
WHERE NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = '$PUB') \gexec
SQL

echo "=== Local: base $RDB con el DDL de E1 (sql/00_setup/002 y sql/01_ddl/011..015)"
LOCAL_DB=postgres local_psql -q <<'SQL'
SELECT 'CREATE DATABASE energia_replica' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'energia_replica') \gexec
SQL
sed "s/energia_db/$RDB/g" sql/00_setup/002_esquemas_extensiones.sql | LOCAL_DB=postgres local_psql -q
for f in sql/01_ddl/01[1-5]_*.sql; do LOCAL_DB=$RDB local_psql -q -f "/sql/01_ddl/$(basename "$f")"; done
LOCAL_DB=$RDB local_psql -q <<'SQL'
CREATE TABLE IF NOT EXISTS control.replica_demo (
  id             integer     PRIMARY KEY,
  texto          text        NOT NULL,
  actualizado_en timestamptz NOT NULL DEFAULT now()
);
SQL

echo "=== Local: suscripcion $SUB (verify-full con el bundle CA de RDS)"
docker compose cp "$CERTS/global-bundle.pem" db:/tmp/global-bundle.pem
CONN="host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=replicador password=$RPW sslmode=verify-full sslrootcert=/tmp/global-bundle.pem"
existe="$(LOCAL_DB=$RDB local_psql -qAt -c "SELECT count(*) FROM pg_subscription s JOIN pg_database d ON d.oid = s.subdbid WHERE d.datname = '$RDB' AND s.subname = '$SUB'")"
if [ "$existe" = 0 ]; then
  LOCAL_DB=$RDB local_psql -q <<SQL
CREATE SUBSCRIPTION $SUB CONNECTION '$CONN' PUBLICATION $PUB WITH (copy_data = true, create_slot = true, slot_name = '$SUB');
SQL
else
  LOCAL_DB=$RDB local_psql -q <<SQL
ALTER SUBSCRIPTION $SUB CONNECTION '$CONN';
ALTER SUBSCRIPTION $SUB REFRESH PUBLICATION;
SQL
fi

echo "=== Espera de la sincronizacion inicial (srsubstate = r en todas las tablas)"
for _ in $(seq 1 360); do
  pendientes="$(LOCAL_DB=$RDB local_psql -qAt -c "SELECT count(*) FROM pg_subscription_rel r JOIN pg_subscription s ON s.oid = r.srsubid WHERE s.subname = '$SUB' AND r.srsubstate <> 'r'")"
  echo "$(date -u +%T) tablas pendientes: $pendientes"
  [ "$pendientes" = 0 ] && break
  sleep 10
done
[ "$pendientes" = 0 ] || { echo "La sincronizacion inicial no termino en 60 min" >&2; exit 1; }
LOCAL_DB=$RDB local_psql -c "SELECT subname, pid, received_lsn, latest_end_time FROM pg_stat_subscription WHERE subname = '$SUB'"
