"""Llena las hojas del modelo del xlsx desde el DDL final (CSV del catalogo que escribe scripts/xlsx_e1.sh) y el DBML.

Hojas: Int_dominio, Clave_primaria, Int_referencial, Restricciones, Dependencias_func, Dominios_ENUM. Ademas agrega a Decisiones
las decisiones nuevas de esta entrega. Respeta encabezados (fila 4), formato (copia el estilo de la fila 5) y las listas desplegables.
"""
import csv
import re
from copy import copy
from pathlib import Path

from openpyxl import load_workbook

import gen_modelo

ROOT = Path(__file__).resolve().parents[1]
XLSX = ROOT / "docs" / "Integridad_Restricciones_Energia.xlsx"
STAGE = ROOT / "data" / "stage"
PRIMERA_FILA = 5
CODIGO_FUENTE = {"simem_E17D25": "F01", "simem_055A4D": "F02", "socrata_tq63-itzr": "F03", "socrata_hp9r-jxuu": "F04", "socrata_57sv-p2fu": "F05",
                 "xm_ListadoRecursos": "F07", "divipola_gdxc-w37w": "F08", "divipola_vcjz-niiq": "F08", "xm_CapEfecNeta": "F10", "xm_ListadoAgentes": "F11"}


def leer(nombre: str) -> list[dict]:
    with (STAGE / f"meta_{nombre}.csv").open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def escribir(ws, filas: list[list]) -> None:
    """Limpia desde la fila 5 y escribe copiando el estilo de la fila 5 de cada columna (las listas desplegables ya cubren hasta la fila 200)."""
    estilo = [ws.cell(PRIMERA_FILA, c) for c in range(1, ws.max_column + 1)]
    for fila in ws.iter_rows(min_row=PRIMERA_FILA, max_row=max(ws.max_row, PRIMERA_FILA)):
        for celda in fila:
            celda.value = None
    for i, valores in enumerate(filas):
        for j, valor in enumerate(valores, start=1):
            celda = ws.cell(PRIMERA_FILA + i, j, valor)
            origen = estilo[j - 1]
            celda.font, celda.border, celda.alignment, celda.fill = copy(origen.font), copy(origen.border), copy(origen.alignment), copy(origen.fill)


def origen_ficha(src: str) -> str:
    """'simem_E17D25.Fecha' -> 'F01.Fecha'; varias fuentes separadas por coma."""
    if src in ("-", ""):
        return "- (surrogate o derivada)"
    partes = []
    for tramo in src.split(", "):
        fuente, _, columna = tramo.partition(".")
        partes.append(f"{CODIGO_FUENTE.get(fuente, fuente)}.{columna}")
    return ", ".join(partes)


INVALIDOS = {  # ejemplos invalidos que se prueban en sql/05_pruebas
    ("energia.planta", "codigo"): "'AB' (2 caracteres) o 'abcd' (minusculas)", ("energia.estacion", "codigo"): "'12345' (5 digitos)",
    ("energia.sensor", "codigo"): "'ab12'", ("energia.agente", "codigo_sic"): "'AB'", ("energia.departamento", "codigo"): "'A1'",
    ("energia.municipio", "codigo"): "'0A999'", ("energia.municipio", "departamento_codigo"): "'99' (no existe en departamento)",
    ("energia.estacion", "latitud"): "40", ("energia.estacion", "longitud"): "10", ("energia.estacion", "altitud"): "7000",
    ("energia.departamento", "latitud"): "40", ("energia.municipio", "longitud"): "10", ("energia.estacion", "fecha_suspension"): "anterior a fecha_instalacion",
    ("energia.generacion_horaria_planta", "fecha_hora"): "'2030-01-01 05:30:00+00' (minutos != 0)", ("energia.generacion_horaria_planta", "energia_kwh"): "-1",
    ("energia.generacion_horaria_planta", "version_codigo"): "'TXZ' (no existe) o una version de menor orden que la guardada",
    ("energia.generacion_diaria_planta", "real_estimada_kwh"): "-5", ("energia.generacion_diaria_planta", "programada_despacho_kwh"): "-1",
    ("energia.generacion_diaria_planta", "programada_redespacho_kwh"): "-1", ("energia.capacidad_planta", "capacidad_kw"): "0",
    ("energia.capacidad_planta", "vigencia"): "'empty' o un rango que solapa otro de la misma planta",
    ("energia.generacion_mensual_upme", "periodo"): "'2030-01-15' (dia 15)", ("energia.generacion_mensual_upme", "generacion_total_gwh"): "-1",
    ("energia.generacion_mensual_upme", "minimo_gwh"): "mayor que maximo_gwh", ("energia.sensor", "valor_max"): "menor o igual que valor_min",
    ("energia.observacion", "valor"): "60 en el sensor 0068 (fuera de rango) o -9998 (centinela)", ("energia.planta", "estado"): "'DESCONOCIDO'",
    ("energia.version_liquidacion", "codigo"): "'ZZ9'",
}
POR_TIPO = [(r"^date", "'2025-02-30'"), (r"^timestamp", "'no es una fecha'"), (r"^(numeric|integer|smallint|bigint)", "'abc'"), (r"^boolean", "'quizas'"),
            (r"^jsonb", "'{no es json'"), (r"^daterange", "'(2020-01-01,2019-01-01)'")]


def invalido(tabla: str, c: dict, enums: dict[str, str]) -> str:
    if (tabla, c["columna"]) in INVALIDOS:
        return INVALIDOS[(tabla, c["columna"])]
    if c["identidad"] == "t" or c["generada"] == "t":
        return "- (la genera el motor)"
    if c["tipo"] in enums:
        return "'DESCONOCIDO' (fuera del ENUM)"
    for patron, ejemplo in POR_TIPO:
        if re.match(patron, c["tipo"]):
            return ejemplo
    return "NULL" if c["admite_null"] == "f" else f"texto mas largo que {c['tipo']}"


def objetos_de(tabla: str, columna: str, restricciones: list[dict], triggers: list[dict]) -> list[str]:
    patron = re.compile(rf"\b{re.escape(columna)}\b")
    nombres = [r["nombre"] for r in restricciones if r["tabla"] == tabla and patron.search(r["definicion"])]
    return nombres + [t["nombre"] for t in triggers if t["tabla"] == tabla and t["tipo"] == "t" and patron.search(t["definicion"])]


# ---------------------------------------------------------------- Restricciones: (RN, hipotesis, tabla, operacion, regla, tipo, objeto, caso, SQLSTATE)
RN = [
    ("RN01", "H01", "energia.generacion_diaria_planta", "INSERT/UPDATE", "La energia programada y la real de un dia nunca son negativas", "CHECK", "ck_generacion_diaria_energia", "INSERT con real_estimada_kwh = -5", "23514"),
    ("RN01", "H01", "energia.generacion_horaria_planta", "INSERT/UPDATE", "La energia de una hora nunca es negativa", "CHECK", "ck_generacion_horaria_energia", "INSERT con energia_kwh = -1", "23514"),
    ("RN01", "H01", "energia.generacion_mensual_upme", "INSERT/UPDATE", "Las cifras mensuales de UPME no son negativas y el minimo no supera al maximo", "CHECK", "ck_generacion_mensual_upme_energia", "INSERT con generacion_total_gwh = -1; INSERT con minimo_gwh > maximo_gwh", "23514"),
    ("RN02", "H03", "energia.capacidad_planta", "INSERT/UPDATE", "La capacidad efectiva es positiva", "CHECK", "ck_capacidad_planta_capacidad", "INSERT con capacidad_kw = 0", "23514"),
    ("RN02", "H20", "energia.capacidad_planta", "INSERT/UPDATE", "La vigencia es un rango no vacio y cerrado por abajo", "CHECK", "ck_capacidad_planta_vigencia", "INSERT con vigencia = 'empty'", "23514"),
    ("RN03", "H20", "energia.capacidad_planta", "INSERT/UPDATE", "Una planta no tiene dos capacidades vigentes a la vez (vigencias sin solape)", "EXCLUDE", "ex_capacidad_vigencia", "INSERT de un rango que solapa uno existente de la misma planta", "23P01"),
    ("RN04", "H04", "energia.generacion_horaria_planta", "INSERT/UPDATE", "La resolucion temporal es horaria: minutos y segundos en cero", "CHECK", "ck_generacion_horaria_hora_exacta", "INSERT con fecha_hora = '2030-01-01 05:30:00+00'", "23514"),
    ("RN05", "H21", "energia.planta", "INSERT/UPDATE", "El codigo de planta son 4 caracteres [A-Z0-9]", "CHECK", "ck_planta_codigo", "INSERT con codigo 'AB' o 'abcd'", "23514"),
    ("RN05", "H21", "energia.planta", "INSERT", "El codigo de planta es unico", "UNIQUE", "uq_planta_codigo", "INSERT de un codigo existente", "23505"),
    ("RN05", "H14", "energia.estacion", "INSERT/UPDATE", "El codigo de estacion son 10 digitos (con ceros a la izquierda)", "CHECK", "ck_estacion_codigo", "INSERT con codigo '12345'", "23514"),
    ("RN05", "H06", "energia.agente", "INSERT/UPDATE", "El codigo SIC de agente son 4 caracteres [A-Z0-9]", "CHECK", "ck_agente_codigo", "INSERT con codigo 'AB'", "23514"),
    ("RN05", "H10", "energia.sensor", "INSERT/UPDATE", "El codigo de sensor son 4 digitos", "CHECK", "ck_sensor_codigo", "INSERT con codigo 'ab12'", "23514"),
    ("RN05", "H19", "energia.version_liquidacion", "INSERT/UPDATE", "El codigo de version es TX seguido de un digito, F o R", "CHECK", "ck_version_liquidacion_codigo", "INSERT con codigo 'ZZ9'", "23514"),
    ("RN06", "H12", "energia.generacion_mensual_upme", "INSERT/UPDATE", "El periodo mensual de UPME se guarda como el dia 1", "CHECK", "ck_generacion_mensual_upme_periodo", "INSERT con periodo '2030-01-15'", "23514"),
    ("RN07", "H07", "energia.estacion", "INSERT/UPDATE", "Las coordenadas de la estacion estan dentro de Colombia (latitud -5..16, longitud -84..-66)", "CHECK", "ck_estacion_coordenadas", "INSERT con latitud 40", "23514"),
    ("RN07", "H07", "energia.departamento", "INSERT/UPDATE", "Las coordenadas del departamento estan dentro de Colombia", "CHECK", "ck_departamento_coordenadas", "INSERT con latitud 40", "23514"),
    ("RN07", "H07", "energia.municipio", "INSERT/UPDATE", "Las coordenadas del municipio estan dentro de Colombia", "CHECK", "ck_municipio_coordenadas", "INSERT con longitud 10", "23514"),
    ("RN07", "H07", "energia.estacion", "INSERT/UPDATE", "La altitud esta entre 0 y 6000 m", "CHECK", "ck_estacion_altitud", "INSERT con altitud 7000", "23514"),
    ("RN08", "H08", "energia.municipio", "INSERT/UPDATE", "El codigo DANE del municipio empieza con el de su departamento", "CHECK", "ck_municipio_prefijo_depto", "INSERT de '05999' con departamento '08'", "23514"),
    ("RN16", "H08", "energia.departamento", "INSERT/UPDATE", "El codigo DANE de departamento son 2 digitos", "CHECK", "ck_departamento_codigo", "INSERT con codigo 'A1'", "23514"),
    ("RN16", "H08", "energia.municipio", "INSERT/UPDATE", "El codigo DANE de municipio son 5 digitos", "CHECK", "ck_municipio_codigo", "INSERT con codigo '0A999'", "23514"),
    ("RN09", "H19", "energia.generacion_horaria_planta", "UPDATE / upsert", "Solo se reemplaza una version por otra de orden igual o mayor; una anterior se rechaza", "TRIGGER", "trg_generacion_horaria_version", "UPDATE de una hora TXF a version TX1", "P0001"),
    ("RN10", "H03", "energia.generacion_horaria_planta", "INSERT/UPDATE", "La energia de una hora no supera la capacidad vigente x 1.10 (solo si hay capacidad vigente)", "TRIGGER", "trg_generacion_horaria_capacidad", "INSERT con energia = capacidad x 1.10 + 1", "P0001"),
    ("RN11", "H10", "energia.sensor", "INSERT/UPDATE", "El maximo del rango del sensor supera al minimo y ambos existen o ninguno", "CHECK", "ck_sensor_rango", "UPDATE con valor_max = valor_min", "23514"),
    ("RN11", "H10", "energia.observacion", "INSERT/UPDATE", "El valor esta dentro del rango plausible del sensor", "TRIGGER", "trg_observacion_rango", "INSERT de 60 C en el sensor 0068", "P0001"),
    ("RN11", "H05", "energia.observacion", "INSERT/UPDATE", "Un centinela (-9998, -9999 o el propio del sensor) no entra como valor", "TRIGGER", "trg_observacion_rango", "INSERT de -9998 en el sensor 0068", "P0001"),
    ("RN12", "H17", "energia.estacion", "INSERT/UPDATE", "Una estacion no se suspende antes de instalarse", "CHECK", "ck_estacion_fechas", "INSERT con fecha_suspension < fecha_instalacion", "23514"),
    ("RN13", "DQ07", "control.carga_lote", "INSERT/UPDATE", "Un solo lote en curso por fuente", "UNIQUE parcial", "uq_carga_lote_en_curso", "Dos lotes en_curso de la misma fuente", "23505"),
    ("RN14", "DQ07", "control.carga_lote", "INSERT/UPDATE", "Un lote ok cuadra: leidas = insertadas + actualizadas + omitidas + rechazadas", "CHECK", "ck_carga_lote_contadores", "INSERT ok con leidas 10 e insertadas 3", "23514"),
    ("RN14", "DQ07", "control.carga_lote", "INSERT/UPDATE", "Un lote en curso no tiene fin; uno terminado no termina antes de iniciar", "CHECK", "ck_carga_lote_fechas", "INSERT en_curso con finalizado_en", "23514"),
    ("RN15", "H06", "energia.planta (y estacion, agente, lote)", "INSERT/UPDATE", "Estados y tipos con dominio cerrado por ENUM", "ENUM", "ENUM", "INSERT de planta con estado 'DESCONOCIDO'", "22P02"),
    ("RN17", "H22", "energia.generacion_diaria_planta", "INSERT", "Toda planta que genera existe en el listado de recursos", "FK", "fk_generacion_diaria_planta_planta", "INSERT con planta_id = -1", "23503"),
    ("RN17", "H22", "energia.generacion_horaria_planta", "INSERT", "Toda hora tiene una version de liquidacion existente", "FK", "fk_generacion_horaria_planta_version", "INSERT con version 'TXZ'", "23503"),
    ("RN17", "H18", "energia.observacion", "INSERT", "Toda observacion tiene una estacion del catalogo", "FK", "fk_observacion_estacion", "INSERT con estacion_id = -1", "23503"),
    ("RN17", "H18", "energia.observacion", "INSERT", "Toda observacion tiene un sensor existente", "FK", "fk_observacion_sensor", "INSERT con sensor_id = -1", "23503"),
    ("RN17", "H06", "energia.planta", "DELETE", "Una planta con generacion no se borra (ON DELETE RESTRICT)", "FK", "fk_generacion_diaria_planta_planta", "DELETE de una planta con generacion diaria", "23503"),
    ("H02", "H02", "energia.generacion_horaria_planta", "INSERT", "Una sola cifra por planta y hora", "PRIMARY KEY", "pk_generacion_horaria_planta", "INSERT de la misma (planta, fecha_hora)", "23505"),
    ("H11", "H11", "energia.observacion", "INSERT", "Una sola observacion por estacion, sensor e instante", "PRIMARY KEY", "pk_observacion", "INSERT repetido de la misma clave", "23505"),
    ("NN", "H06", "energia.planta", "INSERT", "Toda planta tiene nombre", "NOT NULL", "nombre", "INSERT con nombre NULL", "23502"),
]

ENUM_USO = {
    "energia.estado_planta": ("energia.planta.estado", "XM: State del listado de recursos solo toma OPERACION y PRUEBAS (con 'Operacion' = OPERACION al normalizar)"),
    "energia.tipo_despacho": ("energia.planta.tipo_despacho", "XM: Disp solo toma dos valores"),
    "energia.estado_agente": ("energia.agente.estado", "XM: State del listado de agentes solo toma OPERACION e INACTIVO"),
    "energia.estado_estacion": ("energia.estacion.estado", "IDEAM: estado del catalogo solo toma Activa, Suspendida y En Mantenimiento"),
    "control.estado_lote": ("control.carga_lote.estado", "Ciclo de vida de un lote: en_curso -> ok | error"),
}

DEPENDENCIAS = [
    ("planta.codigo (F07.Code, tras deduplicar)", "nombre, tecnologia, fuente_energetica, clasificacion, tipo_despacho, agente, estado, fecha_inicio_operacion", "El codigo de recurso determina todos los atributos de la planta: 2 518 codigos distintos en 2 521 filas; PRG1 es el unico con dos nombres (S-04)", "Total (clave candidata)"),
    ("F01.CodigoPlanta", "TipoGeneracion, TipoDespachoRecurso", "En 22 meses (329 998 filas) ninguna planta cambia de TipoGeneracion y solo 1 cambia de TipoDespachoRecurso: son atributos de la planta, no del hecho. Se toman del listado de recursos", "Total (movida a planta)"),
    ("F01.CodigoPlanta", "TipoClasificacion", "NO se cumple: 252 plantas cambian de TipoClasificacion en el tiempo y el vocabulario mezcla tecnologia y clasificacion. No se guarda; se usa RecType del listado", "Descartada"),
    ("generacion_diaria_planta (planta_id, fecha)", "programada_despacho_kwh, programada_redespacho_kwh, real_estimada_kwh", "Una cifra de cada serie por planta y dia (H02). Las ventanas del backfill se solapan y repiten filas identicas; 10 claves de ISGG traian valores distintos", "Total (clave compuesta)"),
    ("generacion_horaria_planta (planta_id, fecha_hora)", "energia_kwh, version_codigo", "Se guarda una sola fila por punto: la version de mayor orden. En el origen la clave natural es (planta, hora, version)", "Total (clave compuesta)"),
    ("version_liquidacion.codigo", "orden, descripcion", "El orden de cada version es un atributo del catalogo (S-01, supuesto): no se repite en 2.7 millones de filas", "Total (clave)"),
    ("capacidad_planta (planta_id, dia de la serie CapEfecNeta)", "capacidad_kw", "Cada dia tiene un valor; dias consecutivos con el mismo valor se compactan en un rango de vigencia (925 228 dias -> 2 582 rangos)", "Total (por dia); compactada"),
    ("municipio.codigo", "departamento_codigo, nombre, tipo", "Los 2 primeros digitos del codigo DANE del municipio son el codigo de su departamento (RN08): departamento_codigo es derivable del prefijo, se guarda como FK para poder joinear e indexar", "Total; redundancia justificada"),
    ("estacion.codigo (F04.codigo normalizado con lpad a 10)", "nombre, categoria, tecnologia, estado, municipio, entidad, zona, coordenadas, altitud, fechas", "El catalogo trae cada estacion 2, 4 o 6 veces (10 y 8 digitos, y filas repetidas): 57 706 filas = 9 935 estaciones. 44 estaciones tienen un estado distinto entre sus filas (S-06)", "Total tras normalizar y deduplicar"),
    ("estacion.subzona_hidrografica", "zona_hidrografica, area_hidrografica", "subzona -> zona -> area: dependencia transitiva. Se normalizan zona y area en zona_hidrografica; la subzona queda como texto porque no tiene atributos propios", "Transitiva (aceptada y justificada)"),
    ("sensor.codigo (F05.codigosensor)", "descripcion, unidad, rango plausible", "Cada codigo de sensor tiene una descripcion y una unidad; el 0245 no trae ninguna en el origen", "Total (clave candidata)"),
    ("observacion (estacion_id, sensor_id, fecha_observacion)", "valor", "Una observacion por estacion, sensor e instante (H11); el origen repite ventanas y se deduplica", "Total (clave compuesta)"),
    ("generacion_mensual_upme (periodo, fuente_energetica_id)", "promedio_mensual_gwh, maximo_gwh, minimo_gwh, generacion_total_gwh", "Una fila por mes y fuente: 2 786 filas sin duplicados (F03)", "Total (clave compuesta)"),
    ("F03.generacion_total_gwh de la fuente y del mes", "porcentaje_participacion", "porcentaje = total_fuente / suma(total del mes) x 100: dato derivado, no se almacena; va en analitica.v_participacion_mensual_upme (D09)", "Derivada (no almacenada)"),
    ("agente.codigo_sic (F11.Code, tras deduplicar)", "nombre, actividad, estado, fecha_inicio_operacion", "5 codigos aparecen dos veces (una fila INACTIVO antigua y una OPERACION nueva, o el nombre cambia): queda la OPERACION mas reciente (S-05)", "Total tras deduplicar"),
]

PK_JUSTIFICACION = {
    "departamento": "Codigo DANE como PK natural (D05): es estable y es la clave de cruce oficial",
    "municipio": "Codigo DANE de 5 digitos como PK natural (D05); sus 2 primeros digitos son el departamento",
    "agente": "Codigo SIC como PK natural: es la clave que usan listado de recursos y SIMEM (CompanyCode / CodigoSICAgente)",
    "version_liquidacion": "El codigo TX1..TXF es corto, estable y es lo que trae la fuente",
    "capacidad_planta": "Subrogada: el rango de vigencia no puede ser parte de una PK; la unicidad la da el EXCLUDE (RN03)",
    "generacion_diaria_planta": "Clave natural compuesta: una cifra por planta y dia (H02)",
    "generacion_horaria_planta": "Clave natural compuesta SIN la version: se guarda una sola fila vigente (D02-rev)",
    "generacion_mensual_upme": "Clave natural compuesta (periodo, fuente)",
    "observacion": "Clave natural compuesta: una observacion por estacion, sensor e instante (H11); sin surrogate para no ensanchar la tabla de mayor volumen",
}


def main() -> None:
    columnas, restricciones, triggers = leer("columnas"), leer("restricciones"), leer("triggers")
    enums = {r["tipo"]: r["valores"] for r in leer("enums")}
    lotes = {r["fuente"]: r for r in leer("lotes")}
    rech = {(r["fuente"], r["regla"]): int(r["filas"]) for r in leer("rechazos")}
    sin_capacidad = int(leer("sin_capacidad")[0]["plantas"])
    est, obs = lotes["socrata_hp9r-jxuu"], lotes["ideam_observaciones"]
    h = lotes["simem_055A4D"]
    tablas, _ = gen_modelo.parsear((ROOT / "docs" / "modelo" / "modelo_er.dbml").read_text(encoding="utf-8"))
    por_tabla: dict[str, list[dict]] = {}
    for c in columnas:
        por_tabla.setdefault(f"{c['esquema']}.{c['tabla']}", []).append(c)
    definicion = {(r["tabla"], r["nombre"]): r["definicion"] for r in restricciones + triggers}

    wb = load_workbook(XLSX)

    # ---- Int_dominio
    filas = []
    for tabla, cols in por_tabla.items():
        for c in cols:
            meta = next((x for x in tablas[tabla].columnas if x.nombre == c["columna"]), None)
            objetos = objetos_de(tabla, c["columna"], restricciones, triggers)
            implementacion = "; ".join((["NOT NULL"] if c["admite_null"] == "f" else []) + objetos
                                       + ([f"ENUM {c['tipo']}"] if c["tipo"] in enums else []) + (["GENERATED STORED"] if c["generada"] == "t" else [])
                                       + (["IDENTITY"] if c["identidad"] == "t" else [])) or "-"
            defecto = "IDENTITY" if c["identidad"] == "t" else (c["por_defecto"] or "-")
            filas.append([tabla, c["columna"], origen_ficha(meta.src if meta else "-"), c["tipo"], (meta.regla if meta and meta.regla else "-"),
                          "NO" if c["admite_null"] == "f" else "SI", defecto, c["ejemplo"] or "-", invalido(tabla, c, enums), implementacion])
    escribir(wb["Int_dominio"], filas)

    # ---- Clave_primaria
    filas = []
    for r in restricciones:
        if r["tipo"] != "p":
            continue
        tabla = r["tabla"]
        pk_cols = re.search(r"\(([^)]*)\)", r["definicion"]).group(1).split(", ")
        tipos = [next(c["tipo"] for c in por_tabla[tabla] if c["columna"] == pk) for pk in pk_cols]
        identidad = len(pk_cols) == 1 and next(c["identidad"] for c in por_tabla[tabla] if c["columna"] == pk_cols[0]) == "t"
        tipo_llave = "COMPUESTA" if len(pk_cols) > 1 else "Subrogada" if identidad else "Natural"
        alternas = "; ".join(u["definicion"] for u in restricciones if u["tabla"] == tabla and u["tipo"] == "u") or "-"
        nombre_corto = tabla.split(".")[1]
        evidencia = {
            "planta": f"F07 Code: {lotes['xm_ListadoRecursos']['filas_insertadas']} codigos distintos tras deduplicar 3 repetidos (hallazgos P07)",
            "estacion": f"F04 codigo: {lotes['socrata_hp9r-jxuu']['filas_insertadas']} estaciones cargadas de 9 935 distintas; 57 706 filas con 8 y 10 digitos (S-06)",
            "agente": f"F11 Code: {lotes['xm_ListadoAgentes']['filas_insertadas']} codigos tras deduplicar 5 repetidos",
            "generacion_diaria_planta": f"F01 (CodigoPlanta, Fecha): {lotes['simem_E17D25']['filas_insertadas']} filas cargadas sin duplicados; 749 repetidas identicas omitidas",
            "generacion_horaria_planta": f"F02 (CodigoPlanta, FechaHora, Version) sin duplicados (perfil simem_055A4D); {lotes['simem_055A4D']['filas_insertadas']} puntos cargados",
            "observacion": f"F05 (codigoestacion, codigosensor, fechaobservacion): 0 duplicados en la muestra (perfil_57sv-p2fu, H11); {lotes['ideam_observaciones']['filas_insertadas']} cargadas",
            "generacion_mensual_upme": "F03 (ano, mes, fuente): 0 duplicados en las 2 786 filas (perfil_tq63-itzr)",
            "departamento": "F08 codigo_departamento: 33 filas, 33 distintos", "municipio": "F08 cod_mpio: 1 122 filas, 1 122 distintos",
        }.get(nombre_corto, "Clave surrogate generada por el motor (identity): sin dato de origen que la respalde")
        filas.append([tabla, ", ".join(pk_cols), tipo_llave, ", ".join(tipos), f"PK {r['nombre']}: NOT NULL y unica", alternas, evidencia,
                      PK_JUSTIFICACION.get(nombre_corto, "Surrogate entera: la fuente no trae una clave natural estable" if tipo_llave == "Subrogada" else "-")])
    escribir(wb["Clave_primaria"], filas)

    # ---- Int_referencial
    filas = []
    pk_de = {r["tabla"]: re.search(r"\(([^)]*)\)", r["definicion"]).group(1) for r in restricciones if r["tipo"] == "p"}
    for r in restricciones:
        if r["tipo"] != "f":
            continue
        m = re.match(r"FOREIGN KEY \(([^)]*)\) REFERENCES ([\w.]+)\(([^)]*)\)(.*)", r["definicion"])
        fk, padre, pk_padre, resto = m.groups()
        on_delete = (re.search(r"ON DELETE ([A-Z ]+?)(?: ON|$)", resto) or [None, "NO ACTION"])[1]
        on_update = (re.search(r"ON UPDATE ([A-Z ]+?)(?: ON|$)", resto) or [None, "NO ACTION"])[1]
        nula = next(c["admite_null"] for c in por_tabla[r["tabla"]] if c["columna"] == fk) == "t"
        razon = {"CASCADE": "la fila hija no existe sin la padre", "RESTRICT": "una fila en uso no se borra (protege la historia)"}[on_delete]
        filas.append([padre, pk_padre, r["tabla"], fk, "1:N", "SI" if nula else "NO", on_delete, on_update,
                      f"{r['nombre']}: {fk} debe existir en {padre}. ON DELETE {on_delete}: {razon}. ON UPDATE {on_update}: la clave se propaga si se corrige"])
    escribir(wb["Int_referencial"], filas)

    # ---- Restricciones
    filas = []
    for codigo, hip, tabla, operacion, regla, tipo, objeto, caso, sqlstate in RN:
        sql = enums.get("energia.estado_planta", "") and f"CREATE TYPE energia.estado_planta AS ENUM ({enums['energia.estado_planta']}); y los demas ENUM de sql/01_ddl/011_tipos.sql" if tipo == "ENUM" else \
              "NOT NULL" if tipo == "NOT NULL" else definicion.get((tabla, objeto)) or next((v for (t, n), v in definicion.items() if n == objeto), "-")
        filas.append([codigo, hip, tabla, operacion, regla, tipo + (f" {objeto}" if tipo not in ("ENUM", "NOT NULL") else ""), sql, caso, sqlstate])
    escribir(wb["Restricciones"], filas)

    # ---- Dependencias_func
    escribir(wb["Dependencias_func"], [list(d) for d in DEPENDENCIAS])

    # ---- Dominios_ENUM
    escribir(wb["Dominios_ENUM"], [[tipo, enums[tipo], ENUM_USO[tipo][0], ENUM_USO[tipo][1]] for tipo in sorted(enums)])

    # ---- Decisiones: agrega las nuevas (D02 ya figura Revertida; D02-rev, D13 y D14 ya existen)
    ws = wb["Decisiones"]
    existentes = {ws.cell(r, 1).value for r in range(PRIMERA_FILA, ws.max_row + 1)}
    nuevas = [
        ("D18", "Catalogo IDEAM: el codigo de estacion se normaliza con lpad a 10 digitos y se deduplica; queda la fila de 10 digitos de menor posicion.",
         "Una estacion = una fila; FK de observaciones confiable.", "lpad(btrim(codigo), 10, '0'); row_number() por codigo; duplicados a omitidas.",
         "57 706 filas del catalogo = 9 935 estaciones; 100% de los 634 codigos de observaciones existen.",
         "El catalogo trae el mismo codigo con 8 y 10 digitos y filas repetidas (2, 4 o 6 por estacion).",
         "44 estaciones tienen estado distinto entre sus filas: no se reconcilia (el catalogo no trae fecha de corte).", "Decidida"),
        ("D19", "Estaciones cruzan con DIVIPOLA por (departamento, municipio) normalizados (upper, unaccent, trim, sin puntuacion); sin cruce = cuarentena DQ14.",
         "Geografia confiable sin tabla de equivalencias manual.", "energia.normalizar_texto() en columnas GENERATED; LEFT JOIN y rechazo con regla DQ14.",
         f"Estaciones sin cruce (DQ14): {rech[('socrata_hp9r-jxuu', 'DQ14')]} filas del catalogo (Bogota, Cali, Cucuta...). Sus observaciones son DQ15: {rech[('ideam_observaciones', 'DQ15')]} de {obs['filas_leidas']} ({100 * rech[('ideam_observaciones', 'DQ15')] / int(obs['filas_leidas']):.1f}%) quedan en cuarentena.",
         "Decidida en la sesion de E1: 'las que no cruzan van a cuarentena y se reporta el % de cruce'.",
         "Una tabla de equivalencias (Bogota -> BOGOTA, D.C.; Cali -> SANTIAGO DE CALI...) recuperaria casi todo lo perdido. REVISAR antes de E2.", "Pendiente"),
        ("D20", "Rangos plausibles y centinelas propios por sensor (sensor.valor_min, valor_max, centinelas), provisionales.",
         "No cargar valores imposibles (1000 m/s de viento, 995 C).", "Limites fisicos (humedad 0-100, temperatura -15 a 50, viento 0-60) y envolvente real para el resto; 0245 sin rango.",
         f"{rech[('ideam_observaciones', 'DQ08')]} centinelas (DQ08) y {rech[('ideam_observaciones', 'DQ09')]} fuera de rango (DQ09) quedan en cuarentena.",
         "Los datos de un dia (~12 h) no alcanzan para fijar rangos definitivos.", "Revisar los rangos cuando se acumule historia; el sensor 0260 (evaporacion) parece pegado en 883 mm.", "Pendiente"),
        ("D21", "Operadores: ListadoAgentes de la API XM es la tabla maestra; 5 codigos repetidos se deduplican (queda OPERACION mas reciente).",
         "FK planta -> agente confiable con nombre de operador.", "xm_agentes.py + carga con row_number().", "713 agentes; los 149 CompanyCode del listado de recursos existen.",
         "ListadoAgentes existe en ListadoMetricas con codigo SIC, nombre, actividad y estado.", "Perdida del historial de agentes inactivos con el mismo codigo.", "Decidida"),
        ("D22", "Capacidad: la regla de tolerancia es energia horaria <= capacidad vigente x 1.10 y la vigencia termina el ultimo dia extraido (2026-10-31), sin extrapolar.",
         "Validar generacion contra capacidad con datos reales.", "Trigger RN10 condicional + filtro previo en la carga.",
         f"{rech.get(('simem_055A4D', 'RN10'), 0)} puntos (planta, hora) de {h['filas_insertadas']} cargados superan capacidad x 1.10 y van a cuarentena (RN10); {sin_capacidad} plantas sin capacidad vigente al 2026-10-31.",
         "kW x 1 h = kWh solo si la capacidad es constante dentro de la hora.", "Subir la tolerancia o tratar los excesos como alerta en vez de rechazo.", "Decidida"),
    ]
    siguiente = ws.max_row + 1
    estilo_filas = [ws.cell(siguiente - 1, c) for c in range(1, 9)]
    for fila in nuevas:
        if fila[0] in existentes:
            continue
        for j, valor in enumerate(fila, start=1):
            celda = ws.cell(siguiente, j, valor)
            origen = estilo_filas[j - 1]
            celda.font, celda.border, celda.alignment, celda.fill = copy(origen.font), copy(origen.border), copy(origen.alignment), copy(origen.fill)
        siguiente += 1

    wb.save(XLSX)
    print(f"xlsx actualizado: Int_dominio {len(por_tabla)} tablas, {len(restricciones)} restricciones, {len(RN)} reglas, {len(DEPENDENCIAS)} dependencias, {len(enums)} ENUM")


if __name__ == "__main__":
    main()
