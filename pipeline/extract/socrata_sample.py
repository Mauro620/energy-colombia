"""Descarga una muestra paginada por dataset a data/raw/<id>/sample.json y 200 filas a data/sample/<id>.csv."""
import argparse
import csv
import json

import requests

from pipeline.common_raw import escribir_una_vez
from pipeline.common import RAW, SAMPLE, TIMEOUT, load_config, new_session

PAGE_SIZE = 1000


class NonTabular(Exception):
    pass


def fetch_sample(
    session: requests.Session, domain: str, dataset_id: str, n_rows: int, where: str | None
) -> list[dict]:
    rows: list[dict] = []
    while len(rows) < n_rows:
        limit = min(PAGE_SIZE, n_rows - len(rows))
        params = {"$limit": limit, "$offset": len(rows), "$order": ":id"}
        if where:
            params["$where"] = where
        response = session.get(f"https://{domain}/resource/{dataset_id}.json", params=params, timeout=TIMEOUT)
        if 400 <= response.status_code < 500:
            raise NonTabular(response.text[:200])
        response.raise_for_status()
        page = response.json()
        rows += page
        if len(page) < limit:
            break
    return rows


def write_csv(path, rows: list[dict]) -> None:
    fieldnames: list[str] = []
    for row in rows:
        fieldnames += [k for k in row if k not in fieldnames]
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            # Columnas anidadas (ubicacion, url) se guardan como JSON
            writer.writerow({k: json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else v for k, v in row.items()})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--n", type=int, help="filas por dataset (anula config.yaml)")
    parser.add_argument("--only", help="procesar solo este ID")
    args = parser.parse_args()

    config = load_config()
    session = new_session()
    SAMPLE.mkdir(parents=True, exist_ok=True)
    for source in config["sources"]:
        dataset_id = source["id"]
        if args.only and args.only != dataset_id:
            continue
        if (RAW / dataset_id / "sample.json").exists():  # data/raw es inmutable
            print(f"{dataset_id}: sample.json ya existe, omitido")
            continue
        n_rows = args.n or source.get("sample_rows") or config["sample_rows"]
        try:
            rows = fetch_sample(session, config["domain"], dataset_id, n_rows, source.get("where"))
        except NonTabular as exc:
            print(f"{dataset_id}: SALTADO, no tabular por Socrata ({exc})")
            continue
        out_dir = RAW / dataset_id
        out_dir.mkdir(parents=True, exist_ok=True)
        escribir_una_vez(out_dir / "sample.json", json.dumps(rows, ensure_ascii=False))
        write_csv(SAMPLE / f"{dataset_id}.csv", rows[: config["csv_rows"]])
        print(f"{dataset_id}: {len(rows)} filas")


if __name__ == "__main__":
    main()
