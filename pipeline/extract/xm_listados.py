"""Listados de la API XM: guarda el crudo de ListadoMetricas y ListadoRecursos y documenta docs/fuentes/catalogo/xm_recursos.md."""
import json
from datetime import datetime, timezone

import pandas as pd

from pipeline.common import CATALOGO, RAW
from pipeline.common_raw import leer_payload, registrar_error, solicitar, ventanas_pendientes, write_raw
from pipeline.extract.simem_explorar import DIA

URL = "https://servapibi.xm.com.co/lists"
METRICA_RECURSOS = "ListadoRecursos"
FUENTES_SIMEM = {"E17D25": "F01 (generacion diaria por planta)", "055A4D": "F02 (generacion horaria por planta)"}


def extraer(metric_id: str, hoy) -> str:
    fuente = f"xm_{metric_id}"
    if ventanas_pendientes(fuente, hoy, hoy):
        body = {"MetricId": metric_id}
        try:
            response = solicitar("POST", URL, json_body=body)
            items = response.json()["Items"]
            ruta = write_raw(fuente, hoy, hoy, response.content, URL, body, filas=len(items))
        except Exception as exc:
            registrar_error(fuente, hoy, hoy, URL, body, repr(exc))
            raise
        print(f"{fuente}: {len(items)} items -> {ruta or 'omitido (ya existia)'}")
    else:
        print(f"{fuente}: {hoy} ya esta en el manifiesto, no se vuelve a llamar")
    return fuente


def valores(fuente: str, hoy) -> pd.DataFrame:
    items = json.loads(leer_payload(fuente, hoy, hoy))["Items"]
    return pd.DataFrame([e["Values"] for i in items for e in i["ListEntities"]])


def _tabla(encabezados: list[str], filas: list[list]) -> list[str]:
    return ["| " + " | ".join(encabezados) + " |", "|" + "---|" * len(encabezados)] + [
        "| " + " | ".join(str(v).replace("|", "\\|") for v in fila) + " |" for fila in filas
    ]


def _conteo(serie: pd.Series, top: int = 12) -> str:
    return ", ".join(f"{k}={v}" for k, v in serie.value_counts().head(top).items())


def metricas_candidatas(metricas: pd.DataFrame, patron: str) -> list[list]:
    mascara = (metricas["MetricName"] + " " + metricas["MetricDescription"].fillna("")).str.contains(patron, case=False, regex=True)
    return metricas[mascara][["MetricId", "MetricName", "Entity", "Type", "MetricUnits", "MaxDays"]].drop_duplicates().values.tolist()


def cruce_simem(recursos: pd.DataFrame) -> list[str]:
    """P07: la llave del recurso (Code) frente a CodigoPlanta de SIMEM."""
    codigos = set(recursos["Code"])
    normalizados = {c.strip().upper() for c in codigos}
    lineas = []
    for dataset_id, descripcion in FUENTES_SIMEM.items():
        crudo = leer_payload(f"simem_{dataset_id}", DIA, DIA)
        if crudo is None:
            lineas.append(f"- {dataset_id}: sin extraccion de {DIA}; ejecute simem_explorar.")
            continue
        plantas = pd.DataFrame(json.loads(crudo)["result"]["records"])["CodigoPlanta"]
        unicas = set(plantas)
        en_listado = unicas & codigos
        faltan = sorted(unicas - codigos)
        lineas.append(
            f"- {dataset_id} {descripcion}, dia {DIA}: {len(en_listado)} de {len(unicas)} `CodigoPlanta` existen en `Code` "
            f"({100 * len(en_listado) / len(unicas):.1f} %); tras `strip().upper()`: "
            f"{len({p.strip().upper() for p in unicas} & normalizados)}. No cruzan: {', '.join(faltan[:15]) or 'ninguna'}."
        )
        if dataset_id == "E17D25":
            lineas.append(f"  - Recursos del listado presentes en F01: {len(en_listado)} de {len(codigos)} "
                          f"({100 * len(en_listado) / len(codigos):.1f} %); el resto no genero ese dia o no esta en F01.")
    return lineas


def cruce_tipo(recursos: pd.DataFrame) -> list[str]:
    crudo = leer_payload("simem_E17D25", DIA, DIA)
    if crudo is None:
        return []
    f01 = pd.DataFrame(json.loads(crudo)["result"]["records"])[["CodigoPlanta", "TipoGeneracion"]]
    unido = f01.merge(recursos.assign(Type=recursos["Type"].str.upper()), left_on="CodigoPlanta", right_on="Code")
    tabla = pd.crosstab(unido["Type"], unido["TipoGeneracion"])
    return _tabla(["Type (listado, en mayusculas) \\ TipoGeneracion (F01)"] + list(tabla.columns),
                  [[t] + list(fila) for t, fila in tabla.iterrows()])


def escribir_md(fuente_recursos: str, fuente_metricas: str, hoy, recursos: pd.DataFrame, metricas: pd.DataFrame) -> None:
    n = len(recursos)
    fechas = pd.to_datetime(recursos["OperStartdate"], errors="coerce")
    upme = RAW / "tq63-itzr" / "sample.json"
    fuentes_upme = sorted({r["fuente"] for r in json.loads(upme.read_text(encoding="utf-8"))}) if upme.exists() else []
    energeticos = set(recursos["EnerSource"])
    lineas = [
        "# XM: listado de recursos con atributos (`ListadoRecursos`)",
        "",
        "_Generado por `pipeline/extract/xm_listados.py`. No editar a mano._",
        "",
        f"- **Endpoint:** `POST {URL}` con `{{\"MetricId\": \"{METRICA_RECURSOS}\"}}` (no hace falta fecha ni entidad). Crudo: `data/raw/{fuente_recursos}/`.",
        f"- **Como se identifico la metrica:** `ListadoMetricas` (`data/raw/{fuente_metricas}/`) tiene {len(metricas)} entradas; "
        f"`{METRICA_RECURSOS}` aparece {int((metricas['MetricId'] == METRICA_RECURSOS).sum())} veces: "
        + "; ".join(f"\"{r.MetricName}\" (entidad {r.Entity})" for r in metricas[metricas['MetricId'] == METRICA_RECURSOS].itertuples())
        + ". Solo la de entidad Sistema trae atributos.",
        f"- **Filas (recursos):** {n}. Fecha de la foto: {hoy}.",
        "",
        "## Columnas",
        "",
    ] + _tabla(["Columna", "Ejemplo", "Nulos", "Distintos"],
               [[c, recursos[c].iloc[0], int(recursos[c].isna().sum()), recursos[c].nunique()] for c in recursos.columns])
    lineas += [
        "",
        "## Llave del recurso",
        "",
        f"- `Code`: {recursos['Code'].nunique()} distintos en {n} filas, {int(recursos['Code'].isna().sum())} nulos, "
        f"longitud de {recursos['Code'].str.len().min()} a {recursos['Code'].str.len().max()} caracteres "
        f"-> {'unica' if recursos['Code'].is_unique else 'NO unica'}.",
        f"- `Name`: {recursos['Name'].nunique()} distintos en {n} filas.",
        f"- Filas con `Code` repetido: {int(recursos['Code'].duplicated(keep=False).sum())}.",
        "",
    ] + _tabla(list(recursos.columns), recursos[recursos["Code"].duplicated(keep=False)].sort_values("Code").values.tolist()) + [
        "",
        "## Capacidad",
        "",
        "**El listado NO trae capacidad** (ninguna de sus 9 columnas lo es). Metricas candidatas en `ListadoMetricas` "
        "(busqueda por `capacidad|ubicacion|municipio|departamento|coordenadas` en nombre y descripcion; no se llamaron):",
        "",
    ] + _tabla(["MetricId", "Nombre", "Entidad", "Tipo", "Unidad", "MaxDays"], metricas_candidatas(metricas, r"capacidad|ubicaci|municipio|departamento|coorden")
               ) + [
        "",
        "## Tecnologia",
        "",
        f"- `Type`: {_conteo(recursos['Type'])}. Variantes solo por mayusculas: "
        f"{sorted({t for t in set(recursos['Type']) if t != t.upper() and t.upper() in set(recursos['Type'])})} "
        f"(`Solar`={int((recursos['Type'] == 'Solar').sum())} vs `SOLAR`={int((recursos['Type'] == 'SOLAR').sum())}).",
        f"- `EnerSource`: {_conteo(recursos['EnerSource'])}.",
        f"- `RecType`: {_conteo(recursos['RecType'])}.",
        f"- `EnerSource` frente a `fuente` de UPME (`tq63-itzr`, {len(fuentes_upme)} valores): "
        f"coinciden {len(energeticos & set(fuentes_upme))} de {len(energeticos)} valores de XM; "
        f"solo en XM: {sorted(energeticos - set(fuentes_upme))}; solo en UPME: {sorted(set(fuentes_upme) - energeticos)}.",
        "",
        "`Type` del listado frente a `TipoGeneracion` de F01 (plantas de F01 que cruzan por codigo):",
        "",
    ] + cruce_tipo(recursos) + [
        "",
        "## Agente",
        "",
        f"- `CompanyCode`: {recursos['CompanyCode'].nunique()} agentes distintos, {int(recursos['CompanyCode'].isna().sum())} nulos. Mayores: {_conteo(recursos['CompanyCode'], 8)}.",
        "- F02 trae `CodigoSICAgente` (92 agentes en el dia explorado): ver `simem_055A4D.md`.",
        "",
        "## Ubicacion",
        "",
        "**El listado NO trae ubicacion** (ni municipio, ni departamento, ni coordenadas). "
        "Ver las metricas candidatas arriba; ninguna de ellas es por municipio.",
        "",
        "## Otros atributos",
        "",
        f"- `Disp`: {_conteo(recursos['Disp'])}.",
        f"- `State`: {_conteo(recursos['State'])} (variantes de mayusculas: `OPERACION` vs `Operacion`).",
        f"- `OperStartdate`: de {fechas.min().date()} a {fechas.max().date()}; {int(fechas.isna().sum())} nulos o no interpretables.",
        "",
        "## Cruce de la llave con SIMEM (P07)",
        "",
    ] + cruce_simem(recursos)
    (CATALOGO / "xm_recursos.md").write_text("\n".join(lineas) + "\n", encoding="utf-8")


def main() -> None:
    hoy = datetime.now(timezone.utc).date()
    fuente_metricas = extraer("ListadoMetricas", hoy)
    fuente_recursos = extraer(METRICA_RECURSOS, hoy)
    raw = json.loads(leer_payload(fuente_metricas, hoy, hoy))["Items"]
    metricas = pd.DataFrame([e["Values"] for i in raw for e in i["ListEntities"]])
    escribir_md(fuente_recursos, fuente_metricas, hoy, valores(fuente_recursos, hoy), metricas)
    print("docs/fuentes/catalogo/xm_recursos.md escrito")


if __name__ == "__main__":
    main()
