-- Catalogo version_liquidacion. El orden es el SUPUESTO S-01 (docs/decisiones/0002-modelo-e1.md): TX1 < TX2 < TXR < TXF < TX3 < TX4.
-- Idempotente; si el orden se corrige, el ON CONFLICT lo actualiza (la carga y el trigger RN09 leen la tabla).
INSERT INTO energia.version_liquidacion (codigo, orden, descripcion) VALUES
  ('TX1', 1, 'Primera liquidacion de la operacion'),
  ('TX2', 2, 'Segunda liquidacion'),
  ('TXR', 3, 'Liquidacion mensual cercana a la facturacion (TXR)'),
  ('TXF', 4, 'Liquidacion mensual final de facturacion (TXF)'),
  ('TX3', 5, 'Ajuste #1 de la liquidacion de un mes'),
  ('TX4', 6, 'Ajuste #2 de la liquidacion de un mes')
ON CONFLICT (codigo) DO UPDATE SET orden = EXCLUDED.orden, descripcion = EXCLUDED.descripcion
  WHERE (energia.version_liquidacion.orden, energia.version_liquidacion.descripcion) IS DISTINCT FROM (EXCLUDED.orden, EXCLUDED.descripcion);
