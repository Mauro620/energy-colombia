#!/usr/bin/env bash
# Prueba de PITR: marcador -> espera a latest-restorable-time -> DELETE de un mes de generacion diaria ->
# restauracion a 1 minuto antes del DELETE (mismo SG, subnet group y parameter group) -> verificacion.
# Variable opcional: MES=AAAA-MM-01 (por defecto, el mes completo anterior al ultimo con datos).
# AVISO: el DELETE se queda en la instancia original; la instancia restaurada solo demuestra la recuperacion.
. "$(dirname "$0")/_comun.sh"
cargar_rds

utc() { date -u -d "@$1" +%FT%TZ; }
lrt_epoch() { date -u -d "$(aws rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].LatestRestorableTime' --output text)" +%s; }
esperar_lrt() { # $1 epoch que latest-restorable-time debe superar
  local l
  while l="$(lrt_epoch)"; [ "$l" -le "$1" ]; do
    echo "$(date -u +%T) latest-restorable-time=$(utc "$l") aun no supera $(utc "$1"); espero 30 s"; sleep 30
  done
  echo "latest-restorable-time=$(utc "$l") supera $(utc "$1")"
}
resumen_mes() { rds_psql -qAt -F ' | ' -v mes="$MES" <<'SQL'
SELECT count(*), coalesce(sum(real_estimada_kwh), 0) FROM energia.generacion_diaria_planta
WHERE fecha >= :'mes'::date AND fecha < :'mes'::date + interval '1 month';
SQL
}

if [ -n "${T_DEL:-}" ]; then
  # Reanudacion tras un fallo en el paso 4: T_DEL (epoch del DELETE), MES y ANTES salen del log de la corrida fallida
  : "${MES:?con T_DEL defina tambien MES}" "${ANTES:?con T_DEL defina tambien ANTES (filas | suma)}"
  echo "=== Reanudacion: pasos 1-3 omitidos (DELETE a las $(utc "$T_DEL"))"
else
echo "=== 1. Marcador"
rds_psql -q <<'SQL'
CREATE TABLE IF NOT EXISTS public.pitr_marcador (
  id         serial      PRIMARY KEY,
  nota       text        NOT NULL,
  creado_utc timestamptz NOT NULL DEFAULT clock_timestamp()
);
SQL
T_MARC="$(rds_psql -qAt -c "INSERT INTO public.pitr_marcador (nota) VALUES ('antes del DELETE') RETURNING extract(epoch FROM creado_utc)::bigint")"
echo "marcador creado a las $(utc "$T_MARC")"

echo "=== 2. Espera: latest-restorable-time debe superar el marcador"
esperar_lrt "$T_MARC"
# el punto de restauracion (DELETE - 1 min) debe quedar despues del marcador, con margen por desfase de relojes
while [ $(( $(date +%s) - 65 )) -le "$T_MARC" ]; do sleep 5; done

echo "=== 3. DELETE de un mes de generacion diaria"
MES="${MES:-$(rds_psql -qAt -c "SELECT (date_trunc('month', max(fecha)) - interval '1 month')::date FROM energia.generacion_diaria_planta")}"
ANTES="$(resumen_mes)"
echo "mes $MES antes del DELETE (filas | suma real_estimada_kwh): $ANTES"
T_DEL="$(rds_psql -qAt -c "SELECT extract(epoch FROM clock_timestamp())::bigint")"
rds_psql -q -v mes="$MES" <<'SQL'
DELETE FROM energia.generacion_diaria_planta
WHERE fecha >= :'mes'::date AND fecha < :'mes'::date + interval '1 month';
SQL
DESPUES="$(resumen_mes)"
echo "mes $MES despues del DELETE: $DESPUES (DELETE a las $(utc "$T_DEL"))"
fi

T_OBJ=$(( T_DEL - 60 ))
echo "=== 4. Restauracion a $(utc "$T_OBJ") (1 minuto antes del DELETE)"
esperar_lrt "$T_OBJ"
NUEVO="$RDS_ID-pitr-$(date -u +%Y%m%d%H%M)"
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier "$RDS_ID" --target-db-instance-identifier "$NUEVO" \
  --restore-time "$(utc "$T_OBJ")" \
  --db-instance-class db.t4g.micro --no-multi-az --publicly-accessible --no-deletion-protection \
  --db-subnet-group-name "$RDS_SUBNETS" --vpc-security-group-ids "$RDS_SG" --db-parameter-group-name "$RDS_PARAMS" \
  --tags Key=Proyecto,Value=energia-db Key=Entrega,Value=E2 Key=Origen,Value=pitr \
  --query 'DBInstance.DBInstanceIdentifier' --output text
echo "esperando a que $NUEVO este disponible (suele tardar 10-20 min)"
aws rds wait db-instance-available --db-instance-identifier "$NUEVO"

echo "=== 5. Verificacion en la instancia restaurada"
RDS_HOST="$(aws rds describe-db-instances --db-instance-identifier "$NUEVO" --query 'DBInstances[0].Endpoint.Address' --output text)"
# la contrasena maestra de la restaurada es la de la original (sigue en PGPASSWORD)
MARC="$(rds_psql -qAt -c "SELECT count(*) FROM public.pitr_marcador WHERE nota = 'antes del DELETE'")"
RECUP="$(resumen_mes)"
echo "marcador presente: $MARC (esperado 1)"
echo "mes $MES recuperado: $RECUP (esperado: $ANTES)"
if [ "$MARC" = 1 ] && [ "$RECUP" = "$ANTES" ]; then echo "PITR: PASS"; resultado=0; else echo "PITR: FAIL"; resultado=1; fi

echo "=== 6. Instancia restaurada $NUEVO"
read -r -p "Escriba '$NUEVO' para borrarla ahora (Enter la conserva; destruir.sh la borra despues): " resp
if [ "$resp" = "$NUEVO" ]; then
  aws rds delete-db-instance --db-instance-identifier "$NUEVO" --skip-final-snapshot --delete-automated-backups \
    --query 'DBInstance.DBInstanceStatus' --output text
  aws rds wait db-instance-deleted --db-instance-identifier "$NUEVO"
  echo "$NUEVO borrada"
else
  echo "$NUEVO conservada (genera costo hasta que se borre)"
fi
exit "$resultado"
