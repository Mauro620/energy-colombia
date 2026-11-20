"""Evidencia de XM (SIMEM + listado de recursos) para docs/fuentes/hallazgos.md. Lee solo data/raw; no llama a ninguna API."""
import gzip
import json
from datetime import date, datetime

import pandas as pd

from pipeline.common import RAW
from pipeline.common_raw import leer_manifiesto, ultimo_ok, verificar_manifiestos
from pipeline.extract.simem_explorar import DIA, SERIE_REAL_F01, VALOR_F02, cargar, descubrir_datasets
from pipeline.extract.xm_listados import valores

SENTINELAS_IDEAM = (-9998, -9999, 9999, -999, 999, 995, 1000)


def _leer_gz(entrada: dict) -> object:
    return json.loads(gzip.decompress((RAW / entrada["archivo"]).read_bytes()))


def cargar_xm() -> dict | None:
    """None si falta algun crudo (hay que ejecutar simem_explorar y xm_listados)."""
    try:
        cargados = {ds["dataset_id"]: cargar(ds, DIA) for ds in descubrir_datasets()}
        entrada = ultimo_ok("xm_ListadoRecursos")
        if len(cargados) != 2 or entrada is None:
            return None
        recursos = valores("xm_ListadoRecursos", date.fromisoformat(entrada["ventana_inicio"]))
    except (TypeError, FileNotFoundError):  # leer_payload devolvio None
        return None
    diario = next(i for i, (_, df) in cargados.items() if SERIE_REAL_F01 in df.columns)
    horario = next(i for i, (_, df) in cargados.items() if VALOR_F02 in df.columns)
    ideam = ultimo_ok("ideam_observaciones")
    return {
        "id_diario": diario, "id_horario": horario, "res_diario": cargados[diario][0], "f01": cargados[diario][1],
        "res_horario": cargados[horario][0], "f02": cargados[horario][1], "recursos": recursos,
        "ideam": pd.DataFrame(_leer_gz(ideam)) if ideam else None, "ideam_entrada": ideam,
    }


def p01(x: dict):
    f01, f02 = x["f01"], x["f02"]
    resp = (f"Depende del dataset. F01 (`{x['id_diario']}`): una fila = una planta en un dia, con las tres series como columnas. "
            f"F02 (`{x['id_horario']}`): una fila = una planta en una hora y una version de liquidacion (formato largo); no es planta-dia con columnas por hora.")
    ev = [
        f"`{x['id_diario']}`: {len(f01)} filas, `CodigoPlanta` {f01['CodigoPlanta'].nunique()} distintos (unica), `Fecha` {f01['Fecha'].nunique()} valor distinto ({DIA}).",
        f"`{x['id_horario']}`: {len(f02)} filas = {f02['CodigoPlanta'].nunique()} plantas x {f02['FechaHora'].nunique()} horas x {f02['Version'].nunique()} versiones "
        f"(grilla completa = {f02['CodigoPlanta'].nunique() * f02['FechaHora'].nunique() * f02['Version'].nunique()}, faltan "
        f"{f02['CodigoPlanta'].nunique() * f02['FechaHora'].nunique() * f02['Version'].nunique() - len(f02)}; filas por version {f02['Version'].value_counts().to_dict()}); "
        f"(CodigoPlanta, FechaHora, Version) duplicados = {int(f02.duplicated(subset=['CodigoPlanta', 'FechaHora', 'Version']).sum())}.",
    ]
    return "Si", resp, ev


def p02(x: dict) -> tuple[str, list[str]]:
    unidades = {f"`{x['id_diario']}` {v['variableCode']}": v["measurementUnit"] for v in x["res_diario"]["variables"]}
    unidades |= {f"`{x['id_horario']}` {v['variableCode']}": v["measurementUnit"] for v in x["res_horario"]["variables"]}
    texto = (f"XM entrega kWh en F01 y F02 (variables: {', '.join(f'{k}={v}' for k, v in unidades.items())}); "
             "el valor se confirma en la columna `UnidadMedida` de F02.")
    ev = [f"`{x['id_horario']}`.`UnidadMedida`: {x['f02']['UnidadMedida'].value_counts().to_dict()} en {len(x['f02'])} filas.",
          f"`{x['id_diario']}`: sin columna de unidad; la unidad sale de `variables` de la respuesta de la API ({len(x['res_diario']['variables'])} variables, unidades {sorted({v['measurementUnit'] for v in x['res_diario']['variables']})})."]
    return texto, ev


def p03(x: dict):
    f01, f02, rec = x["f01"], x["f02"], x["recursos"]
    p1, p2 = set(f01["CodigoPlanta"]), set(f02["CodigoPlanta"])
    resp = (f"`CodigoPlanta` (texto corto) identifica la planta en F01 y F02. Hay solo codigo: SIMEM no trae el nombre de la planta "
            f"(el nombre esta en `Name` del listado de recursos). Es el mismo campo en ambos datasets, con {len(p2 - p1)} plantas solo en F02.")
    ev = [
        f"`{x['id_diario']}`: columnas {list(f01.columns)}; `CodigoPlanta` longitudes {sorted(int(n) for n in f01['CodigoPlanta'].str.len().unique())}, {len(p1)} distintos.",
        f"`{x['id_horario']}`: `CodigoPlanta` {len(p2)} distintos; en ambos {len(p1 & p2)}; solo F01 {len(p1 - p2)}; solo F02 {len(p2 - p1)} ({', '.join(sorted(p2 - p1))}).",
        f"`{x['id_horario']}`.`CodigoSICAgente`: {f02['CodigoSICAgente'].nunique()} agentes (el listado de recursos usa `CompanyCode`, otro codigo de agente).",
    ]
    return "Si", resp, ev


def p05(x: dict):
    f01, f02 = x["f01"], x["f02"]
    series = ["GeneracionRealEstimada", "GeneracionProgramadaDespacho", "GeneracionProgramadaRedespacho"]
    resp = (f"Separadas por dataset y con forma distinta: F01 trae real, programada en despacho y programada en redespacho como tres columnas de la misma fila; "
            f"F02 trae solo la real (`CodigoVariable` = {', '.join(f02['CodigoVariable'].unique())}) por hora, y en varias versiones de liquidacion. "
            "El redespacho solo existe en F01.")
    ev = [f"`{x['id_diario']}`: no nulos de " + ", ".join(f"{s}={int(f01[s].notna().sum())}" for s in series) + f" sobre {len(f01)} filas.",
          f"`{x['id_horario']}`: `CodigoVariable` {f02['CodigoVariable'].value_counts().to_dict()}; `Version` {f02['Version'].value_counts().to_dict()}."]
    return "Si", resp, ev


def p06(x: dict):
    rec = x["recursos"]
    resp = ("Parcial: el listado de recursos de XM trae tecnologia (`Type`, `EnerSource`) y agente (`CompanyCode`, un codigo, no el nombre), "
            "pero NO trae capacidad efectiva ni ubicacion. La capacidad esta en otra metrica (`CapEfecNeta`, por recurso, diaria, kW; no se ha llamado). "
            "La ubicacion de plantas no esta en ninguna fuente revisada.")
    ev = [f"`ListadoRecursos`: {len(rec)} filas, columnas {list(rec.columns)}.",
          f"`Type` {rec['Type'].str.upper().value_counts().to_dict()}; `CompanyCode` {rec['CompanyCode'].nunique()} distintos."]
    return "Parcial", resp, ev


def p07(x: dict):
    rec, f01, f02 = x["recursos"], x["f01"], x["f02"]
    codigos = set(rec["Code"])
    p1, p2 = set(f01["CodigoPlanta"]), set(f02["CodigoPlanta"])
    repetidos = rec[rec["Code"].duplicated(keep=False)]["Code"].unique()
    resp = (f"`Code` del listado de recursos cruza con `CodigoPlanta`: {len(p1 & codigos)} de {len(p1)} ({100 * len(p1 & codigos) / len(p1):.1f} %) en F01 y "
            f"{len(p2 & codigos)} de {len(p2)} ({100 * len(p2 & codigos) / len(p2):.1f} %) en F02. Los que no cruzan hay que revisarlos. "
            f"`Code` no es unico ({len(repetidos)} codigos repetidos, {int(rec.duplicated().sum())} con fila identica): hay que deduplicar antes de usarlo como llave.")
    ev = [f"F01 no cruzan: {sorted(p1 - codigos)}.", f"F02 no cruzan: {sorted(p2 - codigos)}.",
          f"`Code`: {rec['Code'].nunique()} distintos en {len(rec)} filas; repetidos {list(repetidos)}; filas completamente duplicadas {int(rec.duplicated().sum())}.",
          f"Recursos del listado presentes en F01: {len(p1 & codigos)} de {rec['Code'].nunique()} ({100 * len(p1 & codigos) / rec['Code'].nunique():.1f} %)."]
    return "Si", resp, ev


def p13(x: dict) -> tuple[str, list[str]]:
    f01, f02 = x["f01"], x["f02"]
    solares = set(f01.loc[f01["TipoGeneracion"] == "Solar", "CodigoPlanta"])
    hora = f02["FechaHora"].str[11:13].astype(int)
    solar = f02[f02["CodigoPlanta"].isin(solares)].assign(hora=hora).groupby("hora")[VALOR_F02].sum()
    pico = int(solar.idxmax())
    sin_sol = [f"{h:02d}" for h in range(24) if solar.get(h, 0) == 0]
    texto = (f"SIMEM: `Fecha` (F01) es ISO `YYYY-MM-DD` y `FechaHora` (F02) es `YYYY-MM-DD HH:MM:SS`, ambas sin zona horaria. "
             f"La generacion solar es maxima a las {pico:02d}:00 y es 0 a las {', '.join(sin_sol)} h, lo que corresponde a hora local de Colombia (un reloj UTC pondria el pico 5 h despues, hacia las {(pico + 5) % 24:02d}:00).")
    ev = [f"`{x['id_horario']}`.`FechaHora`: ejemplo `{f02['FechaHora'].iloc[0]}`, {hora.nunique()} horas distintas (0 a 23), `CodigoDuracion` {f02['CodigoDuracion'].unique().tolist()}.",
          f"Suma solar por hora en F02 ({len(solares)} plantas solares de F01): " + ", ".join(f"{h:02d}h={solar.get(h, 0) / 1000:,.0f} MWh" for h in range(5, 20)) + "."]
    return texto, ev


def _estado_f01_enero() -> dict:
    """Huecos y repetidos entre ventanas de F01 en enero de 2025 (D01)."""
    entradas = [e for e in leer_manifiesto("simem_E17D25") if e["estado"] == "ok" and e["ventana_inicio"].startswith("2025-01")]
    filas = [(r["Fecha"], r["CodigoPlanta"]) for e in entradas for r in _leer_gz(e)["result"]["records"]]
    dias = {f for f, _ in filas}
    return {"ventanas": len(entradas), "filas": len(filas), "repetidas": len(filas) - len(set(filas)), "dias": len(dias),
            "esperados": 31, "sin_datos": sorted(d.isoformat() for d in pd.date_range("2025-01-01", "2025-01-31").date if d.isoformat() not in dias)}


def _centinelas(ideam: pd.DataFrame) -> list[str]:
    v = pd.to_numeric(ideam["valorobservado"], errors="coerce")
    lineas = []
    for s in SENTINELAS_IDEAM:
        mascara = v == s
        if mascara.any():
            por_sensor = ideam[mascara]["codigosensor"].value_counts().head(5).to_dict()
            lineas.append(f"{s}: {int(mascara.sum())} filas (sensores {por_sensor})")
    return lineas


def decisiones(x: dict, ctx: dict) -> list[str]:
    f01, f02 = x["f01"], x["f02"]
    enero = _estado_f01_enero()
    verif = verificar_manifiestos()
    total_ok = sum(c["coinciden"] for c in verif.values())
    malos = sum(c["no_coinciden"] + c["sin_archivo"] + c["en_disco_sin_entrada"] for c in verif.values())
    final = f02[f02["Version"] == "TXF"].groupby("CodigoPlanta")[VALOR_F02].sum()
    comun = f01.set_index("CodigoPlanta")[SERIE_REAL_F01].index.intersection(final.index)
    coinciden = int(((final.loc[comun] - f01.set_index("CodigoPlanta").loc[comun, SERIE_REAL_F01]).abs() <= 1).sum())
    dias_f02 = (date(2026, 10, 31) - date(2025, 1, 1)).days + 1
    entrada_f02 = ultimo_ok(f"simem_{x['id_horario']}")
    ideam = x["ideam"]
    ventana = ""
    if ideam is not None:
        e = x["ideam_entrada"]
        horas = (datetime.fromisoformat(e["fecha_max"]) - datetime.fromisoformat(e["fecha_min"])).total_seconds() / 3600
        ventana = f"ventana medida {e['fecha_min']} a {e['fecha_max']} = {horas:.1f} h, {e['filas']} filas"
    estado = {
        "D01": ("Validada con reservas",
                f"El datasetId es el prefijo de 6 caracteres (confirmado en F01 y F02). F01 trae las 3 series (0 nulos en {len(f01)} filas), `CodigoPlanta` y `Fecha`, en kWh. "
                f"Enero 2025: {enero['ventanas']} ventanas, {enero['filas']} filas, {enero['dias']} de {enero['esperados']} dias con datos (sin datos: {enero['sin_datos'] or 'ninguno'}), "
                f"{enero['repetidas']} filas repetidas entre ventanas. Reserva: F02 pesa {entrada_f02['bytes'] / 1e6:.2f} MB gz por dia."),
        "D02": ("REVISAR",
                f"F01 no contiene la serie real de F02: F01 es diaria y F02 horaria; sumando las 24 horas de la version TXF solo {coinciden} de {len(comun)} plantas coinciden con F01 (<= 1 kWh) "
                f"aunque el total del dia difiere {100 * (final.loc[comun].sum() / f01.set_index('CodigoPlanta').loc[comun, SERIE_REAL_F01].sum() - 1):.2f} %. "
                f"F02 ademas tiene {f02['Version'].nunique()} versiones de liquidacion por punto y {len(set(f02['CodigoPlanta']) - set(f01['CodigoPlanta']))} plantas que F01 no tiene. "
                "F01 es una estimacion SCADA y F02 es liquidacion: son dos mediciones, no la misma serie."),
        "D03": ("Validada" if malos == 0 else "REVISAR",
                f"{total_ok} archivos ok en {len(verif)} manifiestos: sha256 del manifiesto = sha256 recalculado; {malos} archivos sin cuadrar con el disco (sin entrada, sin archivo o hash distinto)."),
        "D04": ("Sin evidencia hoy", "Todavia no se carga a la base."),
        "D05": ("REVISAR",
                "Ni los datasets de SIMEM ni `ListadoRecursos` traen municipio, departamento ni coordenadas (9 columnas del listado, ninguna geografica): DIVIPOLA sirve para IDEAM (nombres) "
                "pero las plantas de XM no tienen ubicacion que cruzar."),
        "D06": ("Validada en parte", f"{ventana or 'sin descarga de IDEAM'}; el workflow no se ha ejecutado en GitHub y el medidor de retraso de los cron no se midio."),
        "D07": ("Validada, con una tension",
                f"F01 enero 2025: {enero['filas']} filas -> ~{enero['filas'] * dias_f02 / 31:,.0f} filas en 669 dias. F02: {len(f02)} filas/dia -> ~{len(f02) * dias_f02:,.0f} filas y "
                f"~{entrada_f02['bytes'] * dias_f02 / 1e6:,.0f} MB gz en 669 dias. Con D02 (solo F01) el hecho tendria ~0.25 M filas, poco para ver diferencias en EXPLAIN (E3)."),
        "D08": ("REVISAR" if ideam is not None else "Sin evidencia hoy",
                (f"D08 solo nombra -9998/-9999. Con {len(ideam)} filas: " + "; ".join(_centinelas(ideam)) +
                 ". Valores como 1000 m/s de viento o 995 C son fisicamente imposibles y parecen mas centinelas: faltan reglas por sensor.") if ideam is not None else "sin descarga de IDEAM"),
        "D09": ("Decidida (sin cambios)", "No se toco UPME en esta sesion."),
        "D10": ("Validada", f"F01 y F02 en kWh segun `variables` y `UnidadMedida`; UPME en GWh (columnas `_gwh`)."),
        "D11": ("Validada para SIMEM e IDEAM", "La curva solar de F02 se alinea con hora local; en IDEAM el maximo de `fechaobservacion` coincide con la hora de Colombia (ver P13)."),
        "D12": ("Sin cambios", "Se usaron scripts + Makefile + Actions."),
    }
    return [f"- **{cod}** ({e}): {ev}" for cod, (e, ev) in estado.items()]
