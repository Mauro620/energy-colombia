-- CHECK. Cada regla: codigo RNxx y la hipotesis Hxx de la hoja Hipotesis_reglas de la que sale.
-- Se aplican sobre tablas ya creadas; ADD CONSTRAINT valida las filas existentes (vacias en una base nueva).

-- RN16 (H08) Codigos DANE: departamento 2 digitos, municipio 5 digitos.
CALL control.agregar_restriccion('energia.departamento', 'ck_departamento_codigo', $$CHECK (codigo ~ '^[0-9]{2}$')$$);
CALL control.agregar_restriccion('energia.municipio', 'ck_municipio_codigo', $$CHECK (codigo ~ '^[0-9]{5}$')$$);

-- RN08 (H08) El codigo DANE del municipio empieza con el codigo de su departamento.
CALL control.agregar_restriccion('energia.municipio', 'ck_municipio_prefijo_depto', $$CHECK (left(codigo, 2) = departamento_codigo)$$);

-- RN05 (H06, H14) Formato de codigos: planta y agente 4 caracteres; estacion 10 digitos (ceros a la izquierda); sensor 4 digitos.
CALL control.agregar_restriccion('energia.planta', 'ck_planta_codigo', $$CHECK (codigo ~ '^[A-Z0-9]{4}$')$$);
CALL control.agregar_restriccion('energia.agente', 'ck_agente_codigo', $$CHECK (codigo_sic ~ '^[A-Z0-9]{4}$')$$);
CALL control.agregar_restriccion('energia.estacion', 'ck_estacion_codigo', $$CHECK (codigo ~ '^[0-9]{10}$')$$);
CALL control.agregar_restriccion('energia.sensor', 'ck_sensor_codigo', $$CHECK (codigo ~ '^[0-9]{4}$')$$);
CALL control.agregar_restriccion('energia.version_liquidacion', 'ck_version_liquidacion_codigo', $$CHECK (codigo ~ '^TX[0-9FR]$')$$);

-- RN07 (H07) Coordenadas dentro de Colombia (caja que incluye las islas): latitud -5..16, longitud -84..-66 (S-10).
CALL control.agregar_restriccion('energia.estacion', 'ck_estacion_coordenadas',
  $$CHECK (latitud BETWEEN -5 AND 16 AND longitud BETWEEN -84 AND -66)$$);
CALL control.agregar_restriccion('energia.departamento', 'ck_departamento_coordenadas',
  $$CHECK ((latitud IS NULL OR latitud BETWEEN -5 AND 16) AND (longitud IS NULL OR longitud BETWEEN -84 AND -66))$$);
CALL control.agregar_restriccion('energia.municipio', 'ck_municipio_coordenadas',
  $$CHECK ((latitud IS NULL OR latitud BETWEEN -5 AND 16) AND (longitud IS NULL OR longitud BETWEEN -84 AND -66))$$);
CALL control.agregar_restriccion('energia.estacion', 'ck_estacion_altitud', $$CHECK (altitud IS NULL OR altitud BETWEEN 0 AND 6000)$$);

-- RN12 (H17) Una estacion no se suspende antes de instalarse.
CALL control.agregar_restriccion('energia.estacion', 'ck_estacion_fechas',
  $$CHECK (fecha_suspension IS NULL OR fecha_instalacion IS NULL OR fecha_suspension >= fecha_instalacion)$$);

-- RN01 (H01) La energia generada nunca es negativa.
CALL control.agregar_restriccion('energia.generacion_diaria_planta', 'ck_generacion_diaria_energia',
  $$CHECK (programada_despacho_kwh >= 0 AND programada_redespacho_kwh >= 0 AND real_estimada_kwh >= 0)$$);
CALL control.agregar_restriccion('energia.generacion_horaria_planta', 'ck_generacion_horaria_energia', $$CHECK (energia_kwh >= 0)$$);
CALL control.agregar_restriccion('energia.generacion_mensual_upme', 'ck_generacion_mensual_upme_energia',
  $$CHECK (promedio_mensual_gwh >= 0 AND maximo_gwh >= 0 AND minimo_gwh >= 0 AND generacion_total_gwh >= 0 AND minimo_gwh <= maximo_gwh)$$);

-- RN04 (H04) La resolucion temporal es horaria: minutos y segundos en cero (en UTC; Colombia no usa horario de verano).
CALL control.agregar_restriccion('energia.generacion_horaria_planta', 'ck_generacion_horaria_hora_exacta',
  $$CHECK (date_trunc('hour', fecha_hora AT TIME ZONE 'UTC') = fecha_hora AT TIME ZONE 'UTC')$$);

-- RN06 (H12) UPME: el periodo mensual se guarda como el dia 1.
CALL control.agregar_restriccion('energia.generacion_mensual_upme', 'ck_generacion_mensual_upme_periodo',
  $$CHECK (EXTRACT(day FROM periodo) = 1)$$);

-- RN02 (H03) La capacidad es positiva y la vigencia es un rango cerrado por abajo y no vacio.
CALL control.agregar_restriccion('energia.capacidad_planta', 'ck_capacidad_planta_capacidad', $$CHECK (capacidad_kw > 0)$$);
CALL control.agregar_restriccion('energia.capacidad_planta', 'ck_capacidad_planta_vigencia',
  $$CHECK (NOT isempty(vigencia) AND NOT lower_inf(vigencia) AND lower_inc(vigencia))$$);

-- RN11 (H10) Rango plausible por sensor: el maximo supera al minimo y ambos existen o ninguno.
CALL control.agregar_restriccion('energia.sensor', 'ck_sensor_rango',
  $$CHECK ((valor_min IS NULL) = (valor_max IS NULL) AND (valor_max IS NULL OR valor_max > valor_min))$$);

-- RN14 (DQ07) Contadores de un lote coherentes: no negativos, fin >= inicio, y un lote ok cuadra leidas = resto.
CALL control.agregar_restriccion('control.carga_lote', 'ck_carga_lote_contadores',
  $$CHECK (filas_leidas >= 0 AND filas_insertadas >= 0 AND filas_actualizadas >= 0 AND filas_omitidas >= 0 AND filas_rechazadas >= 0
           AND (estado <> 'ok' OR filas_leidas = filas_insertadas + filas_actualizadas + filas_omitidas + filas_rechazadas))$$);
CALL control.agregar_restriccion('control.carga_lote', 'ck_carga_lote_fechas',
  $$CHECK ((estado = 'en_curso') = (finalizado_en IS NULL) AND (finalizado_en IS NULL OR finalizado_en >= iniciado_en))$$);
