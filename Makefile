-include .env

export UID_GID := $(shell id -u):$(shell id -g)
PY := docker compose run --rm tools python

.PHONY: up down psql sample profile

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
