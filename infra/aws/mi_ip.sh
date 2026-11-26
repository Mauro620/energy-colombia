#!/usr/bin/env bash
# Imprime la IP publica actual como /32, lista para allowed_cidrs en infra/terraform/terraform.tfvars.
set -euo pipefail
ip="$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')"
[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "respuesta inesperada: $ip" >&2; exit 1; }
echo "$ip/32"
