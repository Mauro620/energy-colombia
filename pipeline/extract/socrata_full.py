"""Descarga completa y paginada de datasets Socrata pequenos (catalogo IDEAM y UPME) con write_raw."""
import json
import os
import time
from datetime import datetime, timezone

from pipeline.common import load_config
from pipeline.common_raw import solicitar, ventanas_pendientes, write_raw

DATASETS = ("hp9r-jxuu", "tq63-itzr")  # catalogo de estaciones IDEAM, produccion mensual UPME
PAGINA = 50_000


def _consultar(domain: str, dataset_id: str, params: dict) -> list[dict]:
    token = os.getenv("SOCRATA_APP_TOKEN")
    return solicitar("GET", f"https://{domain}/resource/{dataset_id}.json", params=params,
                     headers={"X-App-Token": token} if token else None).json()


def descargar(domain: str, dataset_id: str) -> list[dict]:
    filas: list[dict] = []
    while True:
        pagina = _consultar(domain, dataset_id, {"$limit": PAGINA, "$offset": len(filas), "$order": ":id"})
        filas += pagina
        if len(pagina) < PAGINA:
            return filas


def main() -> int:
    domain = load_config()["domain"]
    hoy = datetime.now(timezone.utc).date()
    for dataset_id in DATASETS:
        fuente = f"socrata_{dataset_id}"
        if not ventanas_pendientes(fuente, hoy, hoy):
            print(f"{fuente}: {hoy} ya esta en el manifiesto, no se vuelve a llamar")
            continue
        t0 = time.monotonic()
        esperadas = int(_consultar(domain, dataset_id, {"$select": "count(*)"})[0]["count"])
        filas = descargar(domain, dataset_id)
        if len(filas) != esperadas:
            print(f"ERROR {dataset_id}: se descargaron {len(filas)} filas y count(*) = {esperadas}")
            return 1
        ruta = write_raw(fuente, hoy, hoy, json.dumps(filas, ensure_ascii=False).encode("utf-8"),
                         f"https://{domain}/resource/{dataset_id}.json", {"$order": ":id", "$limit": PAGINA}, filas=len(filas))
        print(f"{fuente}: {len(filas)} filas (count(*) = {esperadas}), {ruta.stat().st_size / 1e6 if ruta else 0:.2f} MB gz, {time.monotonic() - t0:.1f} s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
