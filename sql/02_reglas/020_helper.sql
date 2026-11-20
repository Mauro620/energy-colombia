-- Ayuda para que las reglas sean idempotentes: agrega la restriccion solo si no existe.
CREATE OR REPLACE PROCEDURE control.agregar_restriccion(p_tabla regclass, p_nombre name, p_definicion text)
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = p_tabla AND conname = p_nombre) THEN
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s', p_tabla, p_nombre, p_definicion);
  END IF;
END $$;
