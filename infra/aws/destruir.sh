#!/usr/bin/env bash
# Borra las instancias restauradas por pitr.sh y luego destruye la infraestructura de E2 con terraform.
# No toca el bucket del state (infra/terraform/bootstrap). terraform pide su propio "yes" en cada paso.
. "$(dirname "$0")/_comun.sh"
cargar_rds

echo "Se destruira TODA la infraestructura de E2 ($PROYECTO): RDS y red."
read -r -p "Escriba el nombre del proyecto ($PROYECTO) para continuar: " resp
[ "$resp" = "$PROYECTO" ] || { echo "Cancelado."; exit 1; }

echo "=== Instancias restauradas por pitr.sh"
mapfile -t pitr < <(aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier, '$RDS_ID-pitr-')].DBInstanceIdentifier" --output text | tr '\t' '\n' | sed '/^$/d')
for i in "${pitr[@]}"; do
  echo "borrando $i"
  aws rds modify-db-instance --db-instance-identifier "$i" --no-deletion-protection --apply-immediately >/dev/null
  aws rds delete-db-instance --db-instance-identifier "$i" --skip-final-snapshot --delete-automated-backups >/dev/null
  aws rds wait db-instance-deleted --db-instance-identifier "$i"
done
[ "${#pitr[@]}" -gt 0 ] || echo "ninguna"

echo "=== Suscripcion local (un slot huerfano es inofensivo si la instancia desaparece, pero la suscripcion reintentaria)"
bash infra/aws/apagar_replica.sh || echo "apagar_replica.sh fallo; revise la suscripcion local a mano"

echo "=== terraform: quitar deletion_protection (revise el plan)"
terraform -chdir=infra/terraform apply -no-color -var proteccion=false -target=aws_db_instance.principal
echo "=== terraform destroy (revise el plan)"
terraform -chdir=infra/terraform destroy -no-color -var proteccion=false
