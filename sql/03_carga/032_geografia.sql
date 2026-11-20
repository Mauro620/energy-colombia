-- DIVIPOLA del DANE (D05): departamentos y municipios. Una transaccion y un lote por tabla (DQ06, DQ07).
\echo '--- departamentos'
BEGIN;
SELECT control.iniciar_lote('divipola_vcjz-niiq', 'energia.departamento') AS lote \gset
TRUNCATE staging.stg_divipola_dpto;
\copy staging.stg_divipola_dpto FROM '/stage/divipola_dpto.csv' WITH (FORMAT csv, HEADER true)

WITH base AS (
  SELECT s.*, CASE
      WHEN btrim(codigo_departamento) !~ '^[0-9]{2}$' THEN 'RN16'
      WHEN control.a_numero_coma(latitud) IS NULL OR control.a_numero_coma(longitud) IS NULL THEN 'RN18'
      WHEN control.a_numero_coma(latitud) NOT BETWEEN -5 AND 16 OR control.a_numero_coma(longitud) NOT BETWEEN -84 AND -66 THEN 'RN07'
    END AS regla
  FROM staging.stg_divipola_dpto s),
rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla, 'DIVIPOLA departamento invalido', to_jsonb(b) - 'regla' FROM base b WHERE regla IS NOT NULL RETURNING 1),
up AS (
  INSERT INTO energia.departamento (codigo, nombre, latitud, longitud)
  SELECT btrim(codigo_departamento), btrim(nombre_departamento), control.a_numero_coma(latitud), control.a_numero_coma(longitud)
  FROM base WHERE regla IS NULL
  ON CONFLICT (codigo) DO UPDATE SET nombre = EXCLUDED.nombre, latitud = EXCLUDED.latitud, longitud = EXCLUDED.longitud
    WHERE (energia.departamento.nombre, energia.departamento.latitud, energia.departamento.longitud)
          IS DISTINCT FROM (EXCLUDED.nombre, EXCLUDED.latitud, EXCLUDED.longitud)
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM staging.stg_divipola_dpto) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;

\echo '--- municipios'
BEGIN;
SELECT control.iniciar_lote('divipola_gdxc-w37w', 'energia.municipio') AS lote \gset
TRUNCATE staging.stg_divipola_mpio;
\copy staging.stg_divipola_mpio FROM '/stage/divipola_mpio.csv' WITH (FORMAT csv, HEADER true)

WITH base AS (
  SELECT s.*, CASE
      WHEN btrim(cod_mpio) !~ '^[0-9]{5}$' THEN 'RN16'
      WHEN left(btrim(cod_mpio), 2) <> btrim(cod_dpto) THEN 'RN08'
      WHEN NOT EXISTS (SELECT 1 FROM energia.departamento d WHERE d.codigo = btrim(s.cod_dpto)) THEN 'RN17'
      WHEN control.a_numero_coma(latitud) IS NULL OR control.a_numero_coma(longitud) IS NULL THEN 'RN18'
      WHEN control.a_numero_coma(latitud) NOT BETWEEN -5 AND 16 OR control.a_numero_coma(longitud) NOT BETWEEN -84 AND -66 THEN 'RN07'
    END AS regla
  FROM staging.stg_divipola_mpio s),
rej AS (
  INSERT INTO control.registro_rechazado (lote_id, regla, motivo, registro)
  SELECT :lote, regla, 'DIVIPOLA municipio invalido', to_jsonb(b) - 'regla' FROM base b WHERE regla IS NOT NULL RETURNING 1),
up AS (
  INSERT INTO energia.municipio (codigo, departamento_codigo, nombre, tipo, latitud, longitud)
  SELECT btrim(cod_mpio), btrim(cod_dpto), btrim(nom_mpio), btrim(tipo_municipio), control.a_numero_coma(latitud), control.a_numero_coma(longitud)
  FROM base WHERE regla IS NULL
  ON CONFLICT (codigo) DO UPDATE SET departamento_codigo = EXCLUDED.departamento_codigo, nombre = EXCLUDED.nombre, tipo = EXCLUDED.tipo,
      latitud = EXCLUDED.latitud, longitud = EXCLUDED.longitud
    WHERE (energia.municipio.departamento_codigo, energia.municipio.nombre, energia.municipio.tipo, energia.municipio.latitud, energia.municipio.longitud)
          IS DISTINCT FROM (EXCLUDED.departamento_codigo, EXCLUDED.nombre, EXCLUDED.tipo, EXCLUDED.latitud, EXCLUDED.longitud)
  RETURNING (xmax = 0) AS insertada)
SELECT (SELECT count(*) FROM staging.stg_divipola_mpio) AS leidas, (SELECT count(*) FROM rej) AS rech,
       (SELECT count(*) FILTER (WHERE insertada) FROM up) AS ins, (SELECT count(*) FILTER (WHERE NOT insertada) FROM up) AS act \gset
SELECT control.cerrar_lote(:lote, :leidas, :ins, :act, :leidas - :ins - :act - :rech, :rech);
COMMIT;
