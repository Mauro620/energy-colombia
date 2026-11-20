# 0001. Fase de descubrimiento: no se definen tablas hasta perfilar las fuentes

- **Estado:** aceptada
- **Fecha:** 2026-11-19

## Contexto

Los IDs de las fuentes vienen del documento del equipo, pero no se sabe con certeza que contiene cada dataset, que representa una fila, sus unidades ni sus llaves.

## Decision

No se definen tablas, DDL de negocio ni diagramas ER hasta perfilar las fuentes. Primero se descargan metadata y muestras, se perfilan y se responden las preguntas P01-P16. Lo que parezca requerir una tabla se anota como pregunta en `docs/fuentes/hallazgos.md`.

## Consecuencias

- El modelo se deriva de evidencia (perfil de columnas), no de supuestos.
- Los nombres de columnas salen de la metadata o de la muestra, nunca se inventan.
- `sql/01_ddl` a `sql/08_tuning` quedan vacias hasta cerrar esta fase.
