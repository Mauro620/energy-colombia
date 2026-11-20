#!/usr/bin/env bash
# Llena las hojas Int_dominio, Clave_primaria, Int_referencial, Restricciones, Dependencias_func y Dominios_ENUM y agrega las decisiones nuevas
# en docs/Integridad_Restricciones_Energia.xlsx, leyendo el catalogo de la base energia_db YA creada (make e1). Respeta encabezados y formato.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
export UID_GID="$(id -u):$(id -g)"
copiar() { docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d energia_db -c "\\copy ($2) TO STDOUT WITH CSV HEADER" > "data/stage/meta_$1.csv"; }

copiar columnas "
  SELECT n.nspname AS esquema, c.relname AS tabla, a.attname AS columna, a.attnum AS pos, format_type(a.atttypid, a.atttypmod) AS tipo,
         NOT a.attnotnull AS admite_null, pg_get_expr(d.adbin, d.adrelid) AS por_defecto, a.attgenerated <> '' AS generada, a.attidentity <> '' AS identidad,
         (xpath('/row/v/text()', query_to_xml(format('SELECT %I::text AS v FROM %I.%I WHERE %I IS NOT NULL LIMIT 1', a.attname, n.nspname, c.relname, a.attname), false, true, '')))[1]::text AS ejemplo
  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE n.nspname IN ('energia', 'control') AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped ORDER BY 1, 2, 4"
copiar restricciones "
  SELECT n.nspname || '.' || c.relname AS tabla, k.conname AS nombre, k.contype AS tipo, pg_get_constraintdef(k.oid) AS definicion
  FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('energia', 'control') ORDER BY 1, 3, 2"
copiar triggers "
  SELECT tgrelid::regclass::text AS tabla, tgname AS nombre, 't' AS tipo, pg_get_triggerdef(oid) AS definicion
  FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text LIKE 'energia.%'
  UNION ALL SELECT schemaname || '.' || tablename, indexname, 'i', indexdef FROM pg_indexes WHERE schemaname = 'control' AND indexname = 'uq_carga_lote_en_curso'"
copiar enums "
  SELECT n.nspname || '.' || t.typname AS tipo, string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder) AS valores
  FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid JOIN pg_namespace n ON n.oid = t.typnamespace GROUP BY 1 ORDER BY 1"
copiar lotes "SELECT fuente, filas_leidas, filas_insertadas, filas_actualizadas, filas_omitidas, filas_rechazadas FROM control.carga_lote WHERE estado = 'ok' AND lote_id IN (SELECT max(lote_id) FROM control.carga_lote GROUP BY fuente)"
copiar rechazos "SELECT l.fuente, r.regla, count(*) AS filas FROM control.registro_rechazado r JOIN control.carga_lote l USING (lote_id) WHERE l.lote_id IN (SELECT max(lote_id) FROM control.carga_lote WHERE estado = 'ok' GROUP BY fuente) GROUP BY 1, 2"
copiar sin_capacidad "SELECT count(*) AS plantas FROM energia.planta p WHERE NOT EXISTS (SELECT 1 FROM energia.capacidad_planta c WHERE c.planta_id = p.planta_id AND c.vigencia @> DATE '2026-10-31')"
docker compose run --rm -T tools python scripts/llenar_xlsx_e1.py
