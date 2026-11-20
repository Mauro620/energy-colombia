"""Descarga la metadata de cada dataset Socrata y genera docs/fuentes/<id>.md."""
import json
from datetime import datetime, timezone

import requests

from pipeline.common_raw import escribir_una_vez
from pipeline.common import FUENTES, RAW, TIMEOUT, load_config, new_session


def fetch_metadata(session: requests.Session, domain: str, dataset_id: str) -> dict:
    response = session.get(f"https://{domain}/api/views/{dataset_id}.json", timeout=TIMEOUT)
    response.raise_for_status()
    return response.json()


def fetch_row_count(session: requests.Session, domain: str, dataset_id: str) -> int | None:
    """None si el dataset no es tabular (p. ej. entrada federada que apunta a otro portal)."""
    response = session.get(
        f"https://{domain}/resource/{dataset_id}.json",
        params={"$select": "count(*)"},
        timeout=TIMEOUT,
    )
    if 400 <= response.status_code < 500:
        return None
    response.raise_for_status()
    return int(response.json()[0]["count"])


DATE_TYPES = {"calendar_date", "floating_timestamp", "fixed_timestamp"}


def fetch_date_ranges(session: requests.Session, domain: str, meta: dict) -> dict[str, list[str]]:
    """Minimo y maximo de cada columna de fecha, consultados sobre TODO el dataset (no la muestra)."""
    ranges = {}
    for column in meta.get("columns", []):
        if column.get("dataTypeName") not in DATE_TYPES:
            continue
        field = column["fieldName"]
        response = session.get(
            f"https://{domain}/resource/{meta['id']}.json",
            params={"$select": f"min({field}) as minimo, max({field}) as maximo"},
            timeout=TIMEOUT,
        )
        response.raise_for_status()
        row = response.json()[0]
        ranges[field] = [row.get("minimo"), row.get("maximo")]
    return ranges


def _cell(text: object) -> str:
    return str(text or "-").replace("|", "\\|").replace("\n", " ").strip()


def _common_core(meta: dict) -> dict:
    return meta.get("metadata", {}).get("custom_fields", {}).get("Common Core", {})


def _updated(meta: dict) -> str:
    epoch = meta.get("rowsUpdatedAt")
    if epoch:
        return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    return _common_core(meta).get("Last Update") or "-"


def render_markdown(meta: dict, total_rows: int | None, domain: str, date_ranges: dict) -> str:
    core = _common_core(meta)
    entity = meta.get("attribution") or core.get("Publisher") or "-"
    license_ = (meta.get("license") or {}).get("name") or meta.get("licenseId") or core.get("License") or "-"
    columns = meta.get("columns", [])
    lines = [
        f"# {meta['name']} (`{meta['id']}`)",
        "",
        "_Generado por `pipeline/extract/socrata_metadata.py`. No editar a mano._",
        "",
        f"- **Portal:** https://{domain}/d/{meta['id']}",
        f"- **Entidad publicadora:** {_cell(entity)}",
        f"- **Tipo de activo:** {meta.get('assetType', '-')}",
        f"- **Fecha de actualizacion:** {_updated(meta)}",
        f"- **Licencia:** {_cell(license_)}",
        f"- **Total de filas:** {total_rows if total_rows is not None else 'no disponible por la API Socrata'}",
        f"- **Descripcion:** {_cell(meta.get('description'))}",
    ]
    for field, (minimo, maximo) in date_ranges.items():
        lines.append(f"- **Rango de `{field}` (todo el dataset):** {minimo} a {maximo}")
    homepage = core.get("Homepage")
    if homepage:
        lines.append(f"- **Pagina del origen real:** {homepage}")
    lines += ["", "## Columnas", ""]
    if not columns:
        lines.append(
            "La metadata no trae columnas: es una entrada de catalogo que apunta a otro portal, "
            "no una tabla Socrata."
        )
    else:
        lines += ["| Nombre | Tipo | Descripcion |", "|---|---|---|"]
        lines += [
            f"| {_cell(c.get('fieldName'))} ({_cell(c.get('name'))}) | {_cell(c.get('dataTypeName'))} "
            f"| {_cell(c.get('description'))} |"
            for c in columns
        ]
    return "\n".join(lines) + "\n"


def main() -> None:
    config = load_config()
    session = new_session()
    FUENTES.mkdir(parents=True, exist_ok=True)
    for source in config["sources"]:
        dataset_id = source["id"]
        out_dir = RAW / dataset_id
        meta_path, count_path = out_dir / "metadata.json", out_dir / "count.json"
        if meta_path.exists() and count_path.exists():  # data/raw es inmutable: se reutiliza, no se vuelve a descargar
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            conteo = json.loads(count_path.read_text(encoding="utf-8"))
            total, date_ranges = conteo["total_rows"], conteo["date_ranges"]
            print(f"{dataset_id}: crudo existente, omitido")
        else:
            meta = fetch_metadata(session, config["domain"], dataset_id)
            total = fetch_row_count(session, config["domain"], dataset_id)
            date_ranges = fetch_date_ranges(session, config["domain"], meta)
            escribir_una_vez(meta_path, json.dumps(meta, ensure_ascii=False, indent=2))
            escribir_una_vez(count_path, json.dumps({"total_rows": total, "date_ranges": date_ranges}))
        (FUENTES / f"{dataset_id}.md").write_text(render_markdown(meta, total, config["domain"], date_ranges), encoding="utf-8")
        print(f"{dataset_id}: {meta['name']} | filas={total}")


if __name__ == "__main__":
    main()
