-include .env

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

export UID_GID := $(shell id -u):$(shell id -g)
PY := docker compose run --rm tools python

.PHONY: up down psql sample profile e1 tf-init tf-plan tf-apply migrar paridad replica demo-replica pitr destruir

up:
	docker compose up -d --wait db

down:
	docker compose down

psql:
	docker compose exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

sample:
	$(PY) -m pipeline.extract.socrata_metadata
	$(PY) -m pipeline.extract.socrata_sample

profile:
	$(PY) -m pipeline.profiling.perfilar
	$(PY) -m pipeline.profiling.hallazgos

# Entrega 1 de punta a punta: recrea energia_db, aplana data/raw, ejecuta sql/00 a 05 y guarda evidencias/E1/ejecucion_<fecha>.log
e1:
	bash scripts/e1.sh

# Entrega 2 (AWS). Cada target guarda su salida en evidencias/E2/<target>_<fecha>.log
TF := terraform -chdir=infra/terraform
LOG_E2 = 2>&1 | tee evidencias/E2/$@_$$(date +%Y%m%d_%H%M%S).log

# El bucket del state se crea aparte: tfstate-proyecto-admindb-<account_id>
tf-init:
	$(TF) init -no-color -backend-config="bucket=tfstate-proyecto-admindb-$$(aws sts get-caller-identity --query Account --output text)" $(LOG_E2)

tf-plan:
	$(TF) plan -no-color $(LOG_E2)

# terraform muestra el plan y espera "yes"
tf-apply:
	$(TF) apply -no-color $(LOG_E2)

migrar:
	bash infra/aws/migrar.sh $(LOG_E2)

paridad:
	bash infra/aws/paridad.sh $(LOG_E2)

replica:
	bash infra/aws/replica.sh $(LOG_E2)

demo-replica:
	bash infra/aws/demo_replica.sh $(LOG_E2)

pitr:
	bash infra/aws/pitr.sh $(LOG_E2)

destruir:
	bash infra/aws/destruir.sh $(LOG_E2)
