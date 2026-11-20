-- RN03 (H06) Una planta tiene una sola capacidad vigente a la vez: sin vigencias solapadas. Requiere btree_gist.
CALL control.agregar_restriccion('energia.capacidad_planta', 'ex_capacidad_vigencia',
  'EXCLUDE USING gist (planta_id WITH =, vigencia WITH &&)');

-- RN13 (DQ07) Un solo lote en curso por fuente (UNIQUE parcial).
CREATE UNIQUE INDEX IF NOT EXISTS uq_carga_lote_en_curso ON control.carga_lote (fuente) WHERE estado = 'en_curso';
