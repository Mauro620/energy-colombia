#!/usr/bin/env bash
# Migra energia_db local -> RDS: pg_dump -Fc local y pg_restore --no-owner --no-privileges -j 2, luego ANALYZE.
. "$(dirname "$0")/_comun.sh"
cargar_rds
docker compose up -d --wait db

n="$(rds_psql -qAt -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'energia'")"
[ "$n" = 0 ] || { echo "RDS ya tiene $n tablas en el esquema energia: no se restaura encima." >&2; exit 1; }

mkdir -p "$DUMP_DIR"
echo "=== pg_dump -Fc (local) $(date -u +%FT%TZ)"
docker compose exec -T db pg_dump -Fc -U "$POSTGRES_USER" -d energia_db > "$DUMP_DIR/energia_db.dump"
ls -l "$DUMP_DIR/energia_db.dump"

echo "=== pg_restore -> $RDS_HOST $(date -u +%FT%TZ)"
rc=0
docker run --rm -e PGPASSWORD -v "$CERTS:/certs:ro" -v "$DUMP_DIR:/dump:ro" "postgres:$POSTGRES_VERSION" \
  pg_restore --no-owner --no-privileges -j 2 \
  -d "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_USER sslmode=verify-full sslrootcert=/certs/global-bundle.pem" \
  /dump/energia_db.dump || rc=$?
echo "pg_restore termino con codigo $rc (1 = avisos, p. ej. COMMENT ON EXTENSION sin permiso: revise el log y confirme con paridad.sh)"

echo "=== ANALYZE $(date -u +%FT%TZ)"
rds_psql -c "ANALYZE"
echo "=== Fin $(date -u +%FT%TZ)"
