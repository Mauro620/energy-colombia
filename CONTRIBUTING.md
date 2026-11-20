# Como contribuir

- Una rama por tarea, creada desde `main`: `tipo/descripcion-corta` (ej. `feat/perfilado-ideam`).
- Todo cambio entra por Pull Request. Lo revisa otro integrante; nadie aprueba su propio PR.
- Los scripts SQL van numerados (`001_...sql`) dentro de la carpeta de su etapa en `sql/` y deben ser idempotentes: se pueden ejecutar dos veces sin error ni efectos duplicados (`IF NOT EXISTS`, `CREATE OR REPLACE`, `ON CONFLICT`).
- Nunca se versionan secretos (`.env`, claves AWS) ni datos crudos (`data/raw/`). Solo muestras pequenas en `data/sample/`.
- No se crean tablas del modelo hasta cerrar la fase de descubrimiento (ver `docs/decisiones/0001-fase-descubrimiento.md`).
