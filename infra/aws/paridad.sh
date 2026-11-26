#!/usr/bin/env bash
# Paridad local vs RDS por tabla del esquema energia y la bateria de pruebas de E1 (sql/05_pruebas) contra RDS.
# Ejecutar ANTES de pitr.sh (que borra un mes en RDS) y antes de replica.sh (que agrega control.replica_demo).
. "$(dirname "$0")/_comun.sh"
cargar_rds
docker compose up -d --wait db

# filas por tabla; en hechos suma de energia y min/max de fecha; md5 del contenido en tablas pequenas (<= 100000 filas)
SQL_PARIDAD=$(cat <<'SQL'
SET TimeZone = 'UTC';
CREATE FUNCTION pg_temp.paridad() RETURNS TABLE (tabla text, filas bigint, suma numeric, minimo text, maximo text, huella text)
LANGUAGE plpgsql AS $f$
DECLARE r record; h record;
BEGIN
  FOR r IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'energia' AND c.relkind IN ('r', 'p') ORDER BY c.relname LOOP
    tabla := r.relname; suma := NULL; minimo := NULL; maximo := NULL; huella := NULL;
    EXECUTE format('SELECT count(*) FROM energia.%I', r.relname) INTO filas;
    SELECT v.col_suma, v.col_fecha INTO h FROM (VALUES
      ('generacion_diaria_planta',  'real_estimada_kwh',    'fecha'),
      ('generacion_horaria_planta', 'energia_kwh',          'fecha_hora'),
      ('generacion_mensual_upme',   'generacion_total_gwh', 'periodo'),
      ('observacion',               'valor',                'fecha_observacion')) v(tabla, col_suma, col_fecha)
      WHERE v.tabla = r.relname;
    IF FOUND THEN
      EXECUTE format('SELECT sum(%I), min(%I)::text, max(%I)::text FROM energia.%I', h.col_suma, h.col_fecha, h.col_fecha, r.relname)
        INTO suma, minimo, maximo;
    ELSIF filas <= 100000 THEN
      EXECUTE format('SELECT md5(coalesce(string_agg(t::text, ''|'' ORDER BY t::text), '''')) FROM energia.%I t', r.relname) INTO huella;
    END IF;
    RETURN NEXT;
  END LOOP;
END $f$;
SELECT tabla, filas, suma, minimo, maximo, huella FROM pg_temp.paridad();
SQL
)

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "=== Paridad por tabla (tabla|filas|suma|min|max|md5)"
local_psql -qAt -F '|' <<<"$SQL_PARIDAD" > "$tmp/local.txt"
rds_psql   -qAt -F '|' <<<"$SQL_PARIDAD" > "$tmp/rds.txt"
echo "--- local";  cat "$tmp/local.txt"
echo "--- RDS";    cat "$tmp/rds.txt"
fallo=0
if diff "$tmp/local.txt" "$tmp/rds.txt" > "$tmp/dif.txt"; then
  echo "PARIDAD: PASS ($(wc -l < "$tmp/local.txt") tablas identicas)"
else
  echo "PARIDAD: FAIL"; cat "$tmp/dif.txt"; fallo=1
fi

echo; echo "=== Bateria de pruebas E1 (051 y 052) en local y en RDS"
for f in 051_pruebas_reglas 052_pruebas_calidad; do
  local_psql -f "/sql/05_pruebas/$f.sql" 2>&1 | grep -E '\|.*-> (PASS|FAIL)' > "$tmp/$f.local" || true
  rds_psql < "sql/05_pruebas/$f.sql" 2>&1    | grep -E '\|.*-> (PASS|FAIL)' > "$tmp/$f.rds"   || true
  echo "$f: local PASS=$(grep -c -- '-> PASS' "$tmp/$f.local") FAIL=$(grep -c -- '-> FAIL' "$tmp/$f.local")" \
       "| RDS PASS=$(grep -c -- '-> PASS' "$tmp/$f.rds") FAIL=$(grep -c -- '-> FAIL' "$tmp/$f.rds")"
  if [ -s "$tmp/$f.rds" ] && diff <(sed 's/^[^|]*|//' "$tmp/$f.local" | sort) <(sed 's/^[^|]*|//' "$tmp/$f.rds" | sort) >/dev/null; then
    echo "$f: mismos resultados: PASS"
  else
    echo "$f: FAIL (resultados distintos o vacios)"; fallo=1
  fi
done
exit "$fallo"
