"""Perfila cada data/raw/<id>/sample.json.

Salidas: docs/fuentes/perfil_<id>.md, docs/fuentes/perfil_columnas.csv (mismas columnas que la hoja
Perfil_columnas del xlsx) y, con --escribir-xlsx, esas filas en la hoja desde la fila 5.
"""
import argparse
import itertools
import json
import re

import pandas as pd
from openpyxl import load_workbook

from pipeline.common import FUENTES, RAW, ROOT, load_config

XLSX = ROOT / "docs" / "Integridad_Restricciones_Energia.xlsx"
HOJA = "Perfil_columnas"
FILA_ENCABEZADO, FILA_INICIAL = 4, 5
ISO = r"\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?)?"
MAX_COLS_COMBINACION = 15  # acota la busqueda de llaves compuestas: C(15,3)=455 combinaciones


def _normalizar(value: object) -> object:
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    if pd.isna(value) or (isinstance(value, str) and not value.strip()):  # NaN = clave ausente en el JSON
        return pd.NA
    return str(value)


def cargar_muestra(dataset_id: str) -> pd.DataFrame | None:
    path = RAW / dataset_id / "sample.json"
    if not path.exists():
        return None
    df = pd.DataFrame(json.loads(path.read_text(encoding="utf-8")))
    return df.apply(lambda col: col.map(_normalizar))


def inferir_tipo(values: pd.Series) -> str:
    if values.empty:
        return "vacio"
    if values.isin(["true", "false"]).all():
        return "booleano"
    if values.str.fullmatch(ISO).all():
        return "timestamp" if values.str.contains(r"[T ]\d{2}:").any() else "fecha"
    if pd.to_numeric(values, errors="coerce").notna().all():
        return "entero" if values.str.fullmatch(r"-?\d+").all() else "decimal"
    return "texto"


def perfilar_columna(serie: pd.Series) -> dict:
    values = serie.dropna()
    tipo = inferir_tipo(values)
    perfil = {
        "tipo_inferido": tipo,
        "ejemplo": values.iloc[0] if len(values) else "",
        "pct_nulos": 100 * serie.isna().mean(),
        "distintos": int(values.nunique()),
        "minimo": "",
        "maximo": "",
        "negativos": 0,
        "ceros": 0,
        "ceros_izquierda": bool(values.str.fullmatch(r"0\d+").any()),
    }
    if not len(values):
        return perfil
    if tipo in ("entero", "decimal"):
        numeros = pd.to_numeric(values)
        perfil.update(
            minimo=values[numeros.idxmin()], maximo=values[numeros.idxmax()],
            negativos=int((numeros < 0).sum()), ceros=int((numeros == 0).sum()),
        )
    else:  # las fechas ISO y el texto ordenan bien como cadena
        perfil.update(minimo=values.min(), maximo=values.max())
    return perfil


def buscar_llaves(df: pd.DataFrame) -> dict:
    """Columnas y combinaciones de 2-3 sin nulos ni duplicados en la muestra (no prueban unicidad en origen).

    Los decimales se excluyen: en una medicion continua casi todo valor es unico sin identificar nada.
    """
    sin_nulos = [c for c in df.columns if df[c].notna().all() and inferir_tipo(df[c]) != "decimal"]
    unicas = [c for c in sin_nulos if df[c].is_unique]
    candidatas = sorted(
        (c for c in sin_nulos if c not in unicas and df[c].nunique() > 1), key=lambda c: -df[c].nunique()
    )[:MAX_COLS_COMBINACION]
    combinaciones: list[tuple[str, ...]] = []
    for size in (2, 3):
        for combo in itertools.combinations(candidatas, size):
            if any(set(prev) <= set(combo) for prev in combinaciones):
                continue
            if not df.duplicated(subset=list(combo)).any():
                combinaciones.append(combo)
    return {"unicas": unicas, "combinaciones": combinaciones}


def duplicados_exactos(df: pd.DataFrame) -> int:
    return int(df.duplicated().sum())


def perfilar_dataset(dataset_id: str) -> dict | None:
    df = cargar_muestra(dataset_id)
    if df is None:
        return None
    meta = json.loads((RAW / dataset_id / "metadata.json").read_text(encoding="utf-8"))
    total = json.loads((RAW / dataset_id / "count.json").read_text(encoding="utf-8"))["total_rows"]
    tipos_origen = {c["fieldName"]: c.get("dataTypeName", "") for c in meta.get("columns", [])}
    columnas = {c: perfilar_columna(df[c]) | {"tipo_origen": tipos_origen.get(c, "")} for c in df.columns}
    return {
        "id": dataset_id, "nombre": meta["name"], "df": df, "total_filas": total,
        "columnas": columnas, "llaves": buscar_llaves(df), "duplicados_exactos": duplicados_exactos(df),
    }


def observaciones(nombre: str, p: dict, llaves: dict) -> str:
    notas = [f"inferido: {p['tipo_inferido']}"]
    if nombre in llaves["unicas"]:
        notas.append("sin duplicados en la muestra")
    if p["distintos"] == 1:
        notas.append("constante en la muestra")
    if p["pct_nulos"] > 50:
        notas.append("mayoria nulos")
    if p["ceros_izquierda"]:
        notas.append("ceros a la izquierda: tratar como texto")
    if p["negativos"]:
        notas.append(f"{p['negativos']} negativos")
    if p["ceros"]:
        notas.append(f"{p['ceros']} ceros")
    return "; ".join(notas)


def render_md(r: dict) -> str:
    df, llaves = r["df"], r["llaves"]
    completa = len(df) == r["total_filas"]
    lines = [
        f"# Perfil de {r['nombre']} (`{r['id']}`)",
        "",
        "_Generado por `pipeline/profiling/perfilar.py`. No editar a mano._",
        "",
        f"- Filas en la muestra: {len(df)} de {r['total_filas']} "
        + ("(muestra completa: los duplicados y unicidades valen para todo el dataset)" if completa
           else "(muestra parcial, ordenada por `:id`: unicidades observadas no se confirman en origen)"),
        f"- Filas duplicadas exactas en la muestra: {r['duplicados_exactos']}",
        "",
        "## Columnas",
        "",
        "| Columna | Tipo origen | Tipo inferido | Ejemplo | % nulos | Distintos | Minimo | Maximo | Identifica fila |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for nombre, p in r["columnas"].items():
        lines.append(
            f"| {nombre} | {p['tipo_origen'] or '-'} | {p['tipo_inferido']} | {_c(p['ejemplo'])} "
            f"| {p['pct_nulos']:.1f}% | {p['distintos']} | {_c(p['minimo'])} | {_c(p['maximo'])} "
            f"| {'candidata' if nombre in llaves['unicas'] else '-'} |"
        )
    lines += ["", "## Combinaciones candidatas (2-3 columnas sin nulos ni duplicados en la muestra)", ""]
    lines += [f"- {', '.join(c)}" for c in llaves["combinaciones"][:15]] or ["- ninguna encontrada"]
    return "\n".join(lines) + "\n"


def _c(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")[:60] or "-"


def filas_hoja(resultados: list[dict], encabezados: list[str], codigos: dict[str, str]) -> list[list]:
    """Llena solo lo medido; Unidad, Cruza y Decision quedan en blanco para el equipo."""
    filas = []
    for r in resultados:
        for nombre, p in r["columnas"].items():
            valores = {
                "Cod. fuente": codigos.get(r["id"], r["id"]),
                "Columna en origen": nombre,
                "Tipo en origen": p["tipo_origen"],
                "Ejemplo de valor": p["ejemplo"],
                "% nulos": f"{p['pct_nulos']:.1f}%",
                "Valores distintos": p["distintos"],
                "Minimo": p["minimo"],
                "Maximo": p["maximo"],
                "Identifica la fila?": "SI" if nombre in r["llaves"]["unicas"] else "NO",
                "Observaciones / anomalias": observaciones(nombre, p, r["llaves"]),
            }
            filas.append([valores.get(h, "") for h in encabezados])
    return filas


def escribir_xlsx(wb, filas: list[list]) -> None:
    ws = wb[HOJA]
    for fila in ws.iter_rows(min_row=FILA_INICIAL, max_row=ws.max_row):
        for celda in fila:
            celda.value = None
    for i, valores in enumerate(filas):
        for j, valor in enumerate(valores, start=1):
            ws.cell(row=FILA_INICIAL + i, column=j, value=valor)
    wb.save(XLSX)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--escribir-xlsx", action="store_true", help=f"escribe en la hoja {HOJA} desde la fila {FILA_INICIAL}")
    args = parser.parse_args()

    wb = load_workbook(XLSX)
    encabezados = [c.value for c in wb[HOJA][FILA_ENCABEZADO] if c.value]
    codigos = {
        r[3]: r[0] for r in wb["Inventario_fuentes"].iter_rows(min_row=5, values_only=True) if r[3] and r[3] != "-"
    }
    resultados = []
    for source in load_config()["sources"]:
        r = perfilar_dataset(source["id"])
        if r is None:
            print(f"{source['id']}: SALTADO, sin sample.json")
            continue
        (FUENTES / f"perfil_{r['id']}.md").write_text(render_md(r), encoding="utf-8")
        resultados.append(r)
        print(f"{r['id']}: {len(r['columnas'])} columnas")

    filas = filas_hoja(resultados, encabezados, codigos)
    pd.DataFrame(filas, columns=encabezados).to_csv(FUENTES / "perfil_columnas.csv", index=False)
    if args.escribir_xlsx:
        escribir_xlsx(wb, filas)
        print(f"{len(filas)} filas escritas en {HOJA}")


if __name__ == "__main__":
    main()
