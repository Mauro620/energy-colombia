# Funciones comunes de infra/aws. Uso: . "$(dirname "$0")/_comun.sh"
# Lee `terraform output -json` y la contrasena maestra desde Secrets Manager; la contrasena solo viaja en PGPASSWORD
# (se pasa a docker con `-e PGPASSWORD`, sin valor en la linea de comandos) y nunca se imprime.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ"
CERTS="$RAIZ/infra/aws/certs"
DUMP_DIR="$RAIZ/evidencias/E2"
export AWS_DEFAULT_REGION=us-east-1

[ -f .env ] || { echo ".env no existe" >&2; exit 1; }
# .env puede traer fin de linea CRLF (editado en Windows): se quita el \r
set -a; . <(tr -d '\r' < .env); set +a
: "${POSTGRES_USER:?defina POSTGRES_USER en .env}" "${POSTGRES_VERSION:?defina POSTGRES_VERSION en .env}"

cargar_rds() {
  local tfo secreto s
  tfo="$(terraform -chdir=infra/terraform output -json)"
  RDS_HOST="${RDS_HOST:-$(jq -r .endpoint.value <<<"$tfo")}"
  RDS_PORT="$(jq -r .puerto.value <<<"$tfo")"
  RDS_DB="$(jq -r .db_name.value <<<"$tfo")"
  RDS_ID="$(jq -r .db_identifier.value <<<"$tfo")"
  RDS_SG="$(jq -r .security_group_id.value <<<"$tfo")"
  RDS_SUBNETS="$(jq -r .db_subnet_group.value <<<"$tfo")"
  RDS_PARAMS="$(jq -r .parameter_group.value <<<"$tfo")"
  PROYECTO="$(jq -r .proyecto.value <<<"$tfo")"
  secreto="$(jq -r .secreto_contrasena_arn.value <<<"$tfo")"
  s="$(aws secretsmanager get-secret-value --secret-id "$secreto" --query SecretString --output text)"
  RDS_USER="$(jq -r .username <<<"$s")"
  PGPASSWORD="$(jq -r .password <<<"$s")"
  export PGPASSWORD
}

# psql contra RDS con sslmode=verify-full. Usa la imagen postgres:<version de .env> (no hace falta psql local).
rds_psql() {
  docker run --rm -i -e PGPASSWORD -v "$CERTS:/certs:ro" "postgres:$POSTGRES_VERSION" \
    psql -v ON_ERROR_STOP=1 "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_USER sslmode=verify-full sslrootcert=/certs/global-bundle.pem" "$@"
}

# psql contra el PostgreSQL local (contenedor db). LOCAL_DB cambia la base (por defecto energia_db).
local_psql() {
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "${LOCAL_DB:-energia_db}" "$@"
}
