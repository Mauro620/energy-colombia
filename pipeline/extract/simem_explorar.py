"""Explora SIMEM: descubre el datasetId de F01/F02, extrae un dia a data/raw y documenta docs/fuentes/catalogo/simem_<datasetId>.md.

No usa pydataxm. D01 (cliente propio con requests) y D02 (F01 vs F02) se validan aqui con evidencia.
"""
import argparse
import json
from datetime import date

import pandas as pd
import requests

from pipeline.common import CATALOGO, RAW, load_config
from pipeline.common_raw import leer_payload, registrar_error, solicitar, ventanas_pendientes, write_raw
from pipeline.profiling.perfilar import buscar_llaves

URL = "https://www.simem.co/backend-files/api/PublicData"
DIA = date(2025, 3, 1)
SERIE_REAL_F01, VALOR_F02 = "GeneracionRealEstimada", "Valor"


def descubrir_datasets() -> list[dict]:
    """Entradas Socrata federadas hacia SIMEM. Hipotesis: datasetId = primeros 6 caracteres del uuid de datadetail, en mayusculas."""
    encontrados = []
    for source in load_config()["sources"]:
        path = RAW / source["id"] / "metadata.json"
        if not path.exists():
            continue
        meta = json.loads(path.read_text(encoding="utf-8"))
        home = meta.get("metadata", {}).get("custom_fields", {}).get("Common Core", {}).get("Homepage", "")
        if meta.get("displayType") == "federated" and "simem.co/datadetail/" in home:
            uuid = home.rsplit("/", 1)[-1]
            encontrados.append({"socrata_id": source["id"], "nombre": meta["name"], "uuid": uuid,
                                "dataset_id": uuid.replace("-", "")[:6].upper()})
    return encontrados


def extraer_dia(ds: dict, dia: date) -> None:
    fuente = f"simem_{ds['dataset_id']}"
    if not ventanas_pendientes(fuente, dia, dia):
        print(f"{fuente}: {dia} ya esta en el manifiesto, no se vuelve a llamar")
        return
    params = {"datasetId": ds["dataset_id"], "startDate": dia.isoformat(), "endDate": dia.isoformat()}
    try:
        response = solicitar("GET", URL, params=params)
        resultado = response.json()["result"]
        if resultado["idDataset"] != ds["dataset_id"] or resultado["name"] != ds["nombre"]:
            raise ValueError(f"el datasetId {ds['dataset_id']} devolvio '{resultado['name']}', se esperaba '{ds['nombre']}'")
        ruta = write_raw(fuente, dia, dia, response.content, URL, params, filas=len(resultado["records"]))
        print(f"{fuente}: {len(resultado['records'])} filas -> {ruta or 'omitido (ya existia)'}")
    except Exception as exc:  # se registra y se relanza: la ventana queda pendiente
        registrar_error(fuente, dia, dia, URL, params, repr(exc))
        raise


def cargar(ds: dict, dia: date) -> tuple[dict, pd.DataFrame]:
    resultado = json.loads(leer_payload(f"simem_{ds['dataset_id']}", dia, dia))["result"]
    return resultado, pd.DataFrame(resultado["records"])


def probar_mayusculas(dataset_id: str, dia: date) -> list[tuple[str, str]]:
    """Que variantes de mayusculas acepta el endpoint (se prueba con el dataset mas liviano; no se guarda)."""
    d = dia.isoformat()
    variantes = {
        "datasetId/startDate/endDate (camelCase)": {"datasetId": dataset_id, "startDate": d, "endDate": d},
        "datasetid/startdate/enddate (minusculas)": {"datasetid": dataset_id, "startdate": d, "enddate": d},
        "DatasetId/StartDate/EndDate (PascalCase)": {"DatasetId": dataset_id, "StartDate": d, "EndDate": d},
        "datasetId en minusculas (valor)": {"datasetId": dataset_id.lower(), "startDate": d, "endDate": d},
    }
    salida = []
    for nombre, params in variantes.items():
        try:
            data = requests.get(URL, params=params, timeout=60).json()
            filas = len((data.get("result") or {}).get("records", []))
            salida.append((nombre, f"success={data.get('success')}, {filas} filas"))
        except (requests.RequestException, ValueError) as exc:
            salida.append((nombre, f"error: {exc!r}"[:80]))
    return salida


def _tabla(encabezados: list[str], filas: list[list]) -> list[str]:
    limpiar = lambda v: str(v).replace("|", "\\|").replace("\n", " ")  # noqa: E731
    return ["| " + " | ".join(encabezados) + " |", "|" + "---|" * len(encabezados)] + [
        "| " + " | ".join(limpiar(v) for v in fila) + " |" for fila in filas
    ]


def seccion_columnas(df: pd.DataFrame, columnas_api: list[dict]) -> list[str]:
    filas = []
    for c in columnas_api:
        nombre = c["nameColumn"]
        serie = df[nombre]
        numerica = pd.api.types.is_numeric_dtype(serie)
        minimo, maximo = (serie.min(), serie.max()) if len(serie.dropna()) else ("", "")
        filas.append([nombre, c["dataType"], "numero" if numerica else "texto", serie.dropna().iloc[0] if serie.notna().any() else "",
                      int(serie.isna().sum()), serie.nunique(), minimo, maximo, c.get("description", "")])
    return _tabla(["Columna", "Tipo (API)", "Tipo en el JSON", "Ejemplo", "Nulos", "Distintos", "Minimo", "Maximo", "Descripcion (API)"], filas)


def seccion_llave(df: pd.DataFrame) -> list[str]:
    llaves = buscar_llaves(df.astype(str))
    lineas = [f"Filas: {len(df)}. Filas duplicadas exactas: {int(df.duplicated().sum())}."]
    if llaves["unicas"]:
        lineas.append(f"- Columnas unicas por si solas: {', '.join(llaves['unicas'])}")
    for combo in llaves["combinaciones"][:5]:
        lineas.append(f"- Combinacion sin duplicados: ({', '.join(combo)}); duplicados = {int(df.duplicated(subset=list(combo)).sum())}")
    if not llaves["unicas"] and not llaves["combinaciones"]:
        lineas.append("- Ninguna columna ni combinacion de hasta 3 identifica la fila.")
    return lineas


def seccion_valores(df: pd.DataFrame) -> list[str]:
    lineas = []
    for c in df.columns:
        if not pd.api.types.is_numeric_dtype(df[c]) and df[c].nunique() <= 12:
            conteo = df[c].value_counts()
            lineas.append(f"- `{c}` ({len(conteo)} valores): " + ", ".join(f"{k}={v}" for k, v in conteo.items()))
    return lineas


def seccion_numericas(df: pd.DataFrame) -> list[str]:
    filas = []
    for c in df.select_dtypes("number").columns:
        filas.append([c, int(df[c].isna().sum()), int((df[c] < 0).sum()), int((df[c] == 0).sum()), len(df)])
    return _tabla(["Columna", "Nulos", "Negativos", "Ceros", "Filas"], filas)


def seccion_versiones(df: pd.DataFrame) -> list[str]:
    if "Version" not in df.columns:
        return []
    base = ["CodigoPlanta", "FechaHora"]
    por_punto = df.groupby(base)[VALOR_F02].agg(["count", "nunique"])
    return [
        "",
        "## Versiones de la liquidacion",
        "",
        f"`Version` toma {df['Version'].nunique()} valores: " + ", ".join(f"{k}={v}" for k, v in df["Version"].value_counts().items()) + ".",
        f"Cada (CodigoPlanta, FechaHora) aparece {por_punto['count'].min()}-{por_punto['count'].max()} veces (una por version): "
        f"{int((por_punto['nunique'] > 1).sum())} de {len(por_punto)} puntos tienen valores distintos entre versiones.",
    ]


def comparar(f01: pd.DataFrame, f02: pd.DataFrame) -> tuple[list[str], list[str]]:
    """D02: serie real de F01 (diaria) contra la suma de las 24 horas de F02, por version. Devuelve (comparacion, zona horaria)."""
    real = f01.set_index("CodigoPlanta")[SERIE_REAL_F01]
    filas = []
    for version, grupo in f02.groupby("Version"):
        por_planta = grupo.groupby("CodigoPlanta")[VALOR_F02].agg(["sum", "count"])
        comunes = real.index.intersection(por_planta.index)
        dif = (por_planta.loc[comunes, "sum"] - real.loc[comunes]).abs()
        iguales = int((dif <= 1).sum())
        cerca = int(((dif / real.loc[comunes].abs().where(real.loc[comunes] != 0)) <= 0.01).sum())
        filas.append([version, len(por_planta), len(comunes), iguales, cerca, len(comunes) - iguales,
                      int((por_planta["count"] != 24).sum())])
    solo_f01 = set(real.index) - set(f02["CodigoPlanta"])
    solo_f02 = set(f02["CodigoPlanta"]) - set(real.index)
    comparacion = [
        f"Se compara `{SERIE_REAL_F01}` de F01 (kWh por dia y planta) con la suma de `{VALOR_F02}` de F02 en las 24 horas, por cada version.",
        f"Plantas solo en F01: {len(solo_f01)}; solo en F02: {len(solo_f02)} ({', '.join(sorted(solo_f02))[:120]}).",
        "",
    ] + _tabla(["Version F02", "Plantas F02", "Plantas en ambos", "Coinciden (dif <= 1 kWh)", "Dentro de 1 %", "Difieren (> 1 kWh)",
                "Plantas con horas != 24"], filas)

    final = "TXF" if "TXF" in set(f02["Version"]) else sorted(set(f02["Version"]))[-1]
    suma = f02[f02["Version"] == final].groupby("CodigoPlanta")[VALOR_F02].sum().rename("f02")
    cruce = f01.set_index("CodigoPlanta").join(suma, how="inner")
    cruce["coincide"] = (cruce["f02"] - cruce[SERIE_REAL_F01]).abs() <= 1
    por_tipo = cruce.groupby("TipoGeneracion").agg(n=("coincide", "size"), ok=("coincide", "sum"), f01=(SERIE_REAL_F01, "sum"), f02=("f02", "sum"))
    comparacion += [
        "",
        f"Version {final} frente a F01, por `TipoGeneracion` (energia en kWh):",
        "",
    ] + _tabla(["TipoGeneracion", "Plantas", "Coinciden", "Suma F01", "Suma F02", "Dif. %"],
               [[t, int(r.n), int(r.ok), f"{r.f01:,.0f}", f"{r.f02:,.0f}", f"{100 * (r.f02 - r.f01) / r.f01:.2f}"] for t, r in por_tipo.iterrows()]) + [
        "",
        f"Total del dia: F01 = {cruce[SERIE_REAL_F01].sum():,.0f} kWh, F02 ({final}) = {cruce['f02'].sum():,.0f} kWh "
        f"({100 * (cruce['f02'].sum() / cruce[SERIE_REAL_F01].sum() - 1):.2f} %). "
        f"Plantas con F01 = 0 y F02 != 0: {int(((cruce[SERIE_REAL_F01] == 0) & (cruce['f02'] != 0)).sum())}; "
        f"con F01 != 0 y F02 = 0: {int(((cruce[SERIE_REAL_F01] != 0) & (cruce['f02'] == 0)).sum())}.",
    ]

    solares = set(f01.loc[f01["TipoGeneracion"] == "Solar", "CodigoPlanta"])
    f02 = f02.assign(hora=f02["FechaHora"].str[11:13].astype(int))
    solar_por_hora = f02[f02["CodigoPlanta"].isin(solares)].groupby("hora")[VALOR_F02].sum() / f02["Version"].nunique() / 1000
    zona = [
        f"Plantas solares (segun F01 `TipoGeneracion = Solar`): {len(solares)}; presentes en F02: {len(solares & set(f02['CodigoPlanta']))}.",
        f"Horas distintas en `FechaHora`: {f02['hora'].nunique()} (de 0 a 23). Hora de maxima generacion solar: {int(solar_por_hora.idxmax()):02d}:00.",
        "",
    ] + _tabla(["Hora en FechaHora"] + [f"{h:02d}" for h in range(5, 20)], [["MWh solar"] + [f"{solar_por_hora.get(h, 0):,.0f}" for h in range(5, 20)]])
    return comparacion, zona


def escribir_md(ds: dict, resultado: dict, df: pd.DataFrame, dia: date, comparacion: list[str], zona: list[str] | None,
                mayusculas: list[tuple[str, str]]) -> None:
    meta = resultado["metadata"]
    lineas = [
        f"# SIMEM `{ds['dataset_id']}`: {resultado['name']}",
        "",
        "_Generado por `pipeline/extract/simem_explorar.py`. No editar a mano._",
        "",
        f"- **Origen:** Socrata `{ds['socrata_id']}` (entrada federada) -> https://www.simem.co/datadetail/{ds['uuid']}",
        f"- **Hipotesis del datasetId** (primeros 6 caracteres del uuid, en mayusculas = `{ds['dataset_id']}`): "
        f"{'CONFIRMADA' if (resultado['idDataset'], resultado['name']) == (ds['dataset_id'], ds['nombre']) else 'NO confirmada'}: la API devuelve `idDataset = {resultado['idDataset']}` y el mismo nombre que Socrata.",
        f"- **Endpoint:** `GET {URL}?datasetId=&startDate=&endDate=` (fecha ISO, `endDate` inclusiva: 2 dias dan el doble de filas).",
        f"- **Dia extraido:** {dia} -> {len(df)} filas. Periodicidad {meta['periodicity']}, granularidad {meta['granularity']}, ultima actualizacion {meta['lastUpdate']}.",
        f"- **Descripcion:** {meta['description']}",
        f"- **Columna de fecha del filtro (`filterDate`):** {resultado['filterDate']}",
        "",
        "## Mayusculas de los parametros (prueba hecha con el dataset mas liviano)",
        "",
    ] + [f"- {nombre}: {estado}" for nombre, estado in mayusculas]
    lineas += ["", "## Columnas", ""] + seccion_columnas(df, resultado["columns"])
    lineas += ["", "## Que identifica la fila", ""] + seccion_llave(df)
    lineas += ["", "## Unidad", ""]
    lineas += [f"- `{v['variableCode']}` ({v['variableName']}): {v['measurementUnit']}" for v in resultado["variables"]]
    if "UnidadMedida" in df.columns:
        lineas.append(f"- Columna `UnidadMedida` en el dia: {df['UnidadMedida'].value_counts().to_dict()}")
    lineas += ["", "## Valores de las columnas categoricas (tipo de serie y clasificaciones)", ""] + seccion_valores(df)
    lineas += ["", "## Nulos, negativos y ceros", ""] + seccion_numericas(df)
    lineas += seccion_versiones(df)
    lineas += ["", "## Zona horaria", ""]
    lineas += zona or [f"Sin hora en los datos (granularidad {meta['granularity']}): la zona no aplica a esta fecha."]
    lineas += ["", "## Comparacion F01 vs F02 (D02)", ""] + comparacion
    (CATALOGO / f"simem_{ds['dataset_id']}.md").write_text("\n".join(lineas) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dia", type=date.fromisoformat, default=DIA)
    dia = parser.parse_args().dia

    datasets = descubrir_datasets()
    if len(datasets) != 2:
        raise SystemExit(f"Se esperaban 2 entradas SIMEM (F01 y F02) y se encontraron {len(datasets)}: ejecute primero make sample")
    for ds in datasets:
        extraer_dia(ds, dia)
    cargados = {ds["dataset_id"]: cargar(ds, dia) for ds in datasets}

    diario = next(i for i, (_, df) in cargados.items() if SERIE_REAL_F01 in df.columns)
    horario = next(i for i, (_, df) in cargados.items() if VALOR_F02 in df.columns)
    comparacion, zona = comparar(cargados[diario][1], cargados[horario][1])
    mayusculas = probar_mayusculas(min(cargados, key=lambda i: len(cargados[i][1])), dia)
    for ds in datasets:
        resultado, df = cargados[ds["dataset_id"]]
        escribir_md(ds, resultado, df, dia, comparacion, zona if ds["dataset_id"] == horario else None, mayusculas)
        print(f"docs/fuentes/catalogo/simem_{ds['dataset_id']}.md escrito")


if __name__ == "__main__":
    main()
