"""Genera docs/fuentes/hallazgos.md: responde P01-P16 (hoja Preguntas_fuentes) con lo que permite la muestra."""
import json
import re
from datetime import datetime
from zoneinfo import ZoneInfo

from openpyxl import load_workbook

from pipeline.common import FUENTES, RAW, load_config
from pipeline.profiling import hallazgos_xm
from pipeline.profiling.perfilar import XLSX, perfilar_dataset

SIN_MUESTRA = "no se puede responder con esta muestra"
XM: dict | None = None  # evidencia de SIMEM/listados; None si faltan los crudos (ver main)
UNIDADES = re.compile(r"\b(kWh|MWh|GWh)\b", re.I)
GEO_CODIGO = re.compile(r"dane|divipola|cod\w*_?(depto|dpto|mpio|municipio|departamento)", re.I)


def cargar_contexto() -> dict:
    """Por dataset: metadata, conteo/rangos de fecha, perfil de la muestra (None si no hay) y rol descubierto."""
    ctx = {}
    for source in load_config()["sources"]:
        i = source["id"]
        meta = json.loads((RAW / i / "metadata.json").read_text(encoding="utf-8"))
        conteo = json.loads((RAW / i / "count.json").read_text(encoding="utf-8"))
        perfil = perfilar_dataset(i)
        ctx[i] = {"meta": meta, "conteo": conteo, "perfil": perfil, "rol": _rol(meta, perfil)}
    return ctx


def _publicador(meta: dict) -> str:
    core = meta.get("metadata", {}).get("custom_fields", {}).get("Common Core", {})
    return (meta.get("attribution") or core.get("Publisher") or "").upper()


def _rol(meta: dict, perfil: dict | None) -> str:
    pub = _publicador(meta)
    if re.search(r"\bXM\b", pub):
        return "xm"
    if "UPME" in pub:
        return "upme"
    if "IDEAM" in pub or "HIDROLOG" in pub:
        es_obs = perfil and any(p["tipo_inferido"] == "timestamp" for p in perfil["columnas"].values())
        return "ideam_obs" if es_obs else "ideam_cat"
    return "otro"


def de_rol(ctx: dict, rol: str) -> list[tuple[str, dict]]:
    return [(i, d) for i, d in ctx.items() if d["rol"] == rol]


def _nombre(i: str, d: dict) -> str:
    return f"{d['meta']['name']} (`{i}`)"


def _sin_muestra_xm(ctx: dict) -> str:
    ids = ", ".join(f"`{i}`" for i, _ in de_rol(ctx, "xm"))
    return f"{ids}: entradas de catalogo federadas hacia SIMEM, sin columnas ni filas por la API Socrata"


# Cada manejador devuelve (estado, respuesta, evidencia)
def p01(ctx):
    if XM:
        return hallazgos_xm.p01(XM)
    xm = de_rol(ctx, "xm")
    return ("No", f"{SIN_MUESTRA}: la granularidad (planta-dia con columnas por hora o planta-hora) exige filas de XM.",
            [_sin_muestra_xm(ctx)] + [f"`{i}`: {d['meta'].get('description', '')}" for i, d in xm])


def p02(ctx):
    ev, unidades = [], set()
    for i, d in ctx.items():
        textos = [d["meta"].get("description", "")] + [c.get("description", "") for c in d["meta"].get("columns", [])]
        for t in textos:
            unidades |= {u.upper() for u in UNIDADES.findall(t)}
            if UNIDADES.search(t):
                ev.append(f"`{i}`: \"{t.strip()[:140]}\"")
        gwh = [c["fieldName"] for c in d["meta"].get("columns", []) if c["fieldName"].endswith("_gwh")]
        if gwh:
            ev.append(f"`{i}`: columnas {', '.join(gwh)} (sufijo `_gwh`)")
    if XM:
        texto, ev_xm = hallazgos_xm.p02(XM)
        return ("Si", f"{texto} UPME publica en GWh (columnas `_gwh`). Mezclar XM y UPME exige convertir (1 GWh = 1 000 000 kWh).", ev_xm + [e for e in ev if "tq63" in e])
    xm_dicen = [i for i, d in de_rol(ctx, "xm") if UNIDADES.search(d["meta"].get("description", ""))]
    xm_no = [i for i, _ in de_rol(ctx, "xm") if i not in xm_dicen]
    resp = (f"XM: {', '.join(f'`{i}` dice kWh' for i in xm_dicen) or 'ninguna descripcion declara unidad'}"
            f"{'; sin unidad declarada en ' + ', '.join(f'`{i}`' for i in xm_no) if xm_no else ''}. "
            f"UPME publica en GWh. Unidades detectadas en textos: {', '.join(sorted(unidades)) or 'ninguna'}. "
            "Mezclar XM y UPME exige convertir (1 GWh = 1 000 000 kWh).")
    return ("Parcial", resp, ev)


def p03(ctx):
    if XM:
        return hallazgos_xm.p03(XM)
    return ("No", f"{SIN_MUESTRA}: sin columnas de XM no se sabe que campo identifica la planta.", [_sin_muestra_xm(ctx)])


def _numericas_con_novedad(ctx) -> list[str]:
    ev = []
    for i, d in ctx.items():
        if not d["perfil"]:
            continue
        for c, p in d["perfil"]["columnas"].items():
            if c in ("latitud", "longitud", "altitud"):  # negativos y ceros son validos en coordenadas
                continue
            if p["tipo_inferido"] in ("entero", "decimal") and (p["negativos"] or p["ceros"] or p["pct_nulos"]):
                ev.append(f"`{i}`.`{c}`: {p['negativos']} negativos, {p['ceros']} ceros, {p['pct_nulos']:.1f}% nulos en {len(d['perfil']['df'])} filas")
    return ev


def p04(ctx):
    ev = _numericas_con_novedad(ctx)
    resp = ("Hay datos en la muestra de IDEAM/UPME (lista en evidencia); su significado no sale de la muestra, solo de la descripcion de cada fuente. "
            f"Para XM: {SIN_MUESTRA}.")
    return ("Parcial", resp, ev or ["Ninguna columna numerica de las muestras trae negativos, ceros ni nulos."])


def p05(ctx):
    if XM:
        return hallazgos_xm.p05(XM)
    ev = [f"`{i}`: {d['meta'].get('description', '')}" for i, d in de_rol(ctx, "xm")]
    return ("Parcial", "Segun las descripciones: un dataset trae programada (despacho y redespacho) y real juntas, y otro trae solo la real "
            "(la real aparece en ambos). Falta ver las columnas para saber si van en columnas o en filas.", ev)


def p06(ctx):
    if XM:
        return hallazgos_xm.p06(XM)
    return ("No", f"{SIN_MUESTRA}: capacidad efectiva, tecnologia, operador y ubicacion de plantas no estan en ninguna de las 5 fuentes. "
            "Hace falta F07 (listado de recursos/parametros tecnicos de XM). El campo `tecnologia` del catalogo IDEAM es de estaciones, no de plantas.",
            ["Ninguna columna de plantas en las muestras ni en metadata."])


def p07(ctx):
    if XM:
        return hallazgos_xm.p07(XM)
    return ("No", f"{SIN_MUESTRA}: sin columnas de XM ni de F07 no se puede comparar la llave.", [_sin_muestra_xm(ctx)])


def _ubicacion_invertida(df) -> str | None:
    if not {"ubicaci_n", "latitud", "longitud"} <= set(df.columns):
        return None
    filas = df.dropna(subset=["ubicaci_n", "latitud", "longitud"])
    json_lat = filas["ubicaci_n"].map(lambda s: json.loads(s).get("latitude"))
    invertidas = (json_lat == filas["longitud"]).mean()
    return f"{100 * invertidas:.0f}% de las filas traen en `ubicaci_n.latitude` el valor de la columna `longitud` (lat/long invertidas)"


def p08(ctx):
    ev, resp = [], []
    for i, d in de_rol(ctx, "ideam_cat"):
        p = d["perfil"]
        llaves = p["llaves"]["unicas"]
        geo = [c for c in p["columnas"] if re.search(r"depart|munic|ubica|lat|long|altitud|zona|area", c)]
        parcial = len(p["df"]) < p["total_filas"]
        resp.append(f"{_nombre(i, d)}: candidatas a identificar la estacion {', '.join(f'`{c}`' for c in llaves) or 'ninguna'}"
                    f"{' (solo sobre muestra parcial)' if parcial else ''}. Ubicacion: {', '.join(f'`{c}`' for c in geo)}.")
        ev.append(f"`{i}`: {len(p['df'])} de {p['total_filas']} filas, columnas unicas en muestra: {llaves}")
        inv = _ubicacion_invertida(p["df"])
        if inv:
            ev.append(f"`{i}`: {inv}")
    return ("Parcial" if resp else "No", " ".join(resp) or SIN_MUESTRA, ev)


def p09(ctx):
    ev, resp = [], []
    for i, d in de_rol(ctx, "ideam_obs"):
        df = d["perfil"]["df"]
        if not {"codigosensor", "descripcionsensor", "unidadmedida"} <= set(df.columns):
            continue
        sensores = df.fillna("(nulo)").groupby(["codigosensor", "descripcionsensor", "unidadmedida"]).size().reset_index(name="n")
        resp.append(f"{_nombre(i, d)}: {len(sensores)} combinaciones sensor/descripcion/unidad en la muestra; la frecuencia va dentro del texto de "
                    "`descripcionsensor` (horaria, cada 10 minutos), no en una columna propia.")
        ev += [f"`{i}`: sensor {r.codigosensor} | {r.descripcionsensor} | {r.unidadmedida} | {r.n} filas" for r in sensores.itertuples()]
    return ("Parcial" if resp else "No", " ".join(resp) or SIN_MUESTRA, ev)


def p10(ctx):
    ev, resp = [], []
    for i, d in de_rol(ctx, "ideam_obs") + de_rol(ctx, "ideam_cat"):
        rangos = d["conteo"]["date_ranges"]
        rango = "; ".join(f"`{c}` {a} a {b}" for c, (a, b) in rangos.items()) or "sin columna de fecha de tipo fecha"
        resp.append(f"{_nombre(i, d)}: {d['conteo']['total_rows']} filas; {rango}.")
        deptos = d["perfil"]["columnas"].get("departamento") if d["perfil"] else None
        if deptos:
            ev.append(f"`{i}`.`departamento`: {deptos['distintos']} distintos en la muestra; permite `$where` (ver `pipeline/config.yaml`)")
    return ("Parcial" if resp else "No", " ".join(resp) + " El filtro `$where` por departamento no se probo contra el dataset completo desde este script.", ev)


def p11(ctx):
    ev, resp = [], []
    for i, d in de_rol(ctx, "upme"):
        df = d["perfil"]["df"]
        col = "fuente" if "fuente" in df.columns else None
        if col:
            valores = sorted(df[col].dropna().unique())
            parcial = len(df) < d["perfil"]["total_filas"]
            resp.append(f"{_nombre(i, d)}: {len(valores)} fuentes: {', '.join(valores)}{' (muestra parcial)' if parcial else ''}.")
            ev.append(f"`{i}`.`{col}`: {len(valores)} distintos de {len(df)} filas")
    resp.append(f"Relacion con las tecnologias de XM: {SIN_MUESTRA}.")
    return ("Parcial", " ".join(resp), ev)


def p12(ctx):
    ev, resp = [], []
    for i, d in de_rol(ctx, "upme"):
        df = d["perfil"]["df"]
        if {"ano", "mes"} <= set(df.columns):
            periodo = df["ano"].astype(int) * 100 + df["mes"].astype(int)
            ini, fin = df.loc[periodo.idxmin()], df.loc[periodo.idxmax()]
            resp.append(f"UPME cubre {ini['ano']}-{int(ini['mes']):02d} a {fin['ano']}-{int(fin['mes']):02d} (en la muestra, {len(df)} de {d['perfil']['total_filas']} filas).")
            ev.append(f"`{i}`.`ano`/`mes`: minimo {ini['ano']}-{int(ini['mes']):02d}, maximo {fin['ano']}-{int(fin['mes']):02d}")
    resp.append(f"Periodo de XM y comparabilidad mensual: {SIN_MUESTRA}.")
    return ("Parcial", " ".join(resp), ev)


def p13(ctx):
    ev, resp = [], []
    ahora = {"hora Colombia": datetime.now(ZoneInfo("America/Bogota")).replace(tzinfo=None),
             "UTC": datetime.now(ZoneInfo("UTC")).replace(tzinfo=None)}
    for i, d in ctx.items():
        p = d["perfil"]
        if not p:
            continue
        for c, col in p["columnas"].items():
            if col["tipo_inferido"] in ("timestamp", "fecha"):
                ev.append(f"`{i}`.`{c}`: tipo {col['tipo_origen']}, ejemplo `{col['ejemplo']}`, sin zona horaria en el valor")
        for c, (_, maximo) in d["conteo"]["date_ranges"].items():
            ts = datetime.fromisoformat(maximo)
            difs = {k: abs((v - ts).total_seconds()) / 3600 for k, v in ahora.items()}
            cercano = min(difs, key=difs.get)
            if difs[cercano] < 3:  # solo tiene sentido si el dataset es casi tiempo real
                resp.append(f"`{i}`.`{c}`: el maximo ({maximo}) esta a {difs[cercano]:.1f} h de la {cercano} actual y a {max(difs.values()):.1f} h de la otra: sugiere {cercano}.")
        otros = [c for c, col in p["columnas"].items() if col["tipo_origen"] == "text" and "fecha" in c]
        if otros:
            ev.append(f"`{i}`: {', '.join(otros)} vienen como texto (ej. `{p['columnas'][otros[0]]['ejemplo']}`)")
    if XM:
        texto, ev_xm = hallazgos_xm.p13(XM)
        return ("Si", " ".join([texto] + resp), ev_xm + ev)
    resp.append(f"XM: {SIN_MUESTRA}.")
    return ("Parcial", " ".join(resp), ev)


def p14(ctx):
    ev, resp = [], []
    for i, d in ctx.items():
        p = d["perfil"]
        if not p:
            continue
        combos = [", ".join(c) for c in p["llaves"]["combinaciones"][:3]]
        ev.append(f"`{i}`: {p['duplicados_exactos']} filas duplicadas exactas en {len(p['df'])} filas; columnas unicas {p['llaves']['unicas'] or 'ninguna'}; combinaciones candidatas {combos or 'ninguna'}")
        resp.append(f"{_nombre(i, d)}: {p['duplicados_exactos']} duplicados exactos.")
    resp.append(f"XM: {SIN_MUESTRA}. Una unicidad en muestra parcial no prueba unicidad en origen.")
    return ("Parcial", " ".join(resp), ev)


def p15(ctx):
    ev, resp = [], []
    for i, d in ctx.items():
        p = d["perfil"]
        if not p:
            continue
        cols = list(p["columnas"])
        dane = [c for c in cols if GEO_CODIGO.search(c)]
        nombres = [c for c in cols if c in ("departamento", "municipio")]
        coords = [c for c in cols if c in ("latitud", "longitud", "ubicaci_n")]
        if nombres or coords or dane:
            resp.append(f"`{i}`: codigos DANE {dane or 'ninguno'}; nombres {nombres or 'ninguno'}; coordenadas {coords or 'ninguna'}.")
        ev.append(f"`{i}`: columnas de ubicacion {nombres + coords + dane}")
    resp.append(f"XM: {SIN_MUESTRA}.")
    return ("Parcial", " ".join(resp), ev)


def p16(ctx):
    patron = re.compile(r"mantenim|indisponib", re.I)
    ev = [f"`{i}`: menciona mantenimiento/indisponibilidad en nombre, descripcion o tags" for i, d in ctx.items()
          if patron.search(" ".join([d["meta"]["name"], d["meta"].get("description", ""), *d["meta"].get("tags", [])]))]
    return ("No", f"{SIN_MUESTRA}: ninguna de las 5 fuentes es un dataset de mantenimientos o indisponibilidades de plantas; "
            "no se busco en el portal de XM ni en el catalogo de datos.gov.co.",
            ev or ["Sin coincidencias en metadata de las 5 fuentes."])


MANEJADORES = {f"P{n:02d}": f for n, f in enumerate([p01, p02, p03, p04, p05, p06, p07, p08, p09, p10, p11, p12, p13, p14, p15, p16], 1)}


def preguntas() -> list[tuple[str, str, str]]:
    ws = load_workbook(XLSX, read_only=True)["Preguntas_fuentes"]
    return [(r[0], r[1], r[2]) for r in ws.iter_rows(min_row=5, values_only=True) if r[0]]


def preguntas_abiertas(ctx: dict) -> list[str]:
    abiertas = []
    xm = de_rol(ctx, "xm")
    if xm:
        abiertas.append(f"Las {len(xm)} fuentes de XM no son tablas Socrata: el equipo debe decidir si se consume la API de SIMEM ({', '.join(d['meta']['metadata']['custom_fields']['Common Core'].get('Homepage', '-') for _, d in xm)}) y sobre que fuente se modela la generacion.")
    for i, d in de_rol(ctx, "ideam_obs"):
        rango = d["conteo"]["date_ranges"].get("fechaobservacion")
        if rango:
            abiertas.append(f"`{i}` cubre solo {rango[0]} a {rango[1]} ({d['conteo']['total_rows']} filas): parece una ventana movil de lecturas recientes. Habra que acumular la historia por cuenta propia? Con que frecuencia?")
        df = d["perfil"]["df"]
        if "codigoestacion" in df.columns and df["codigoestacion"].str.startswith("0").any():
            abiertas.append(f"`{i}`.`codigoestacion` trae ceros a la izquierda (ej. `{df['codigoestacion'].iloc[0]}`). Se cruza con `codigo` del catalogo, que aqui se ve sin ceros? Hay que normalizar el formato de la llave antes de cruzar.")
    for i, d in de_rol(ctx, "ideam_cat"):
        inv = _ubicacion_invertida(d["perfil"]["df"])
        if inv:
            abiertas.append(f"`{i}`: {inv}. Que columnas de ubicacion se toman como validas?")
    if de_rol(ctx, "upme"):
        abiertas.append("UPME trae agregados mensuales por fuente (GWh) derivados de XM: guardarlos como tabla propia o recalcularlos desde la generacion de XM?")
    return abiertas


def render(ctx: dict) -> str:
    lines = ["# Hallazgos de la fase de descubrimiento", "",
             "_Generado por `pipeline/profiling/hallazgos.py` a partir de las muestras en `data/raw/` y las hojas del xlsx. No editar a mano._", "",
             "## Datasets", "", "| ID | Nombre | Rol detectado | Filas en origen | Filas en muestra |", "|---|---|---|---|---|"]
    for i, d in ctx.items():
        muestra = len(d["perfil"]["df"]) if d["perfil"] else "sin muestra"
        total = d["conteo"]["total_rows"] if d["conteo"]["total_rows"] is not None else "n/d"
        lines.append(f"| `{i}` | {d['meta']['name']} | {d['rol']} | {total} | {muestra} |")
    lines += ["", "## Preguntas P01-P16", ""]
    for cod, tema, pregunta in preguntas():
        estado, respuesta, evidencia = MANEJADORES[cod](ctx)
        lines += [f"### {cod} ({tema}): {pregunta}", "", f"**Estado:** {estado}. **Respuesta tentativa:** {respuesta}", "", "**Evidencia:**", ""]
        lines += [f"- {e}" for e in evidencia] or ["- ninguna"]
        lines.append("")
    lines += ["## Preguntas abiertas para el modelo", "",
              "Cosas que podrian requerir una tabla o una decision; no se define ninguna tabla en esta fase.", ""]
    lines += [f"- {a}" for a in preguntas_abiertas(ctx)]
    if XM:
        lines += ["", "## Decisiones de la hoja `Decisiones` frente a la evidencia", "",
                  "Validada = la evidencia la respalda; REVISAR = la evidencia la contradice o la deja incompleta; Sin evidencia hoy = aun no se puede medir.", ""]
        lines += hallazgos_xm.decisiones(XM, ctx)
    return "\n".join(lines) + "\n"


def main() -> None:
    global XM
    XM = hallazgos_xm.cargar_xm()
    ctx = cargar_contexto()
    (FUENTES / "hallazgos.md").write_text(render(ctx), encoding="utf-8")
    print(f"hallazgos.md: {len(ctx)} datasets, {len(MANEJADORES)} preguntas")


if __name__ == "__main__":
    main()
