"""Acumula las observaciones del IDEAM (57sv-p2fu), que solo muestra una ventana de ~12 h (D06, DQ12).

Descarga el dataset completo, lo guarda con write_raw y registra min/max de fechaobservacion en el manifiesto.
Falla (codigo 2) si hubo un hueco respecto de la corrida anterior.
"""
import json
import os
import sys
from datetime import datetime

from pipeline.common import load_config
from pipeline.common_raw import leer_manifiesto, solicitar, write_raw

DATASET_ID = "57sv-p2fu"
FUENTE = "ideam_observaciones"
PAGINA = 50_000
CAMPO_FECHA = "fechaobservacion"


def _consultar(domain: str, params: dict) -> list[dict]:
    token = os.getenv("SOCRATA_APP_TOKEN")
    headers = {"X-App-Token": token} if token else None
    return solicitar("GET", f"https://{domain}/resource/{DATASET_ID}.json", params=params, headers=headers).json()


def contar(domain: str) -> int:
    return int(_consultar(domain, {"$select": "count(*)"})[0]["count"])


def descargar(domain: str) -> list[dict]:
    """Pagina con $limit/$offset ordenando por :id hasta una pagina incompleta (DQ01)."""
    filas: list[dict] = []
    numero = 0
    while True:
        numero += 1
        pagina = _consultar(domain, {"$limit": PAGINA, "$offset": len(filas), "$order": ":id"})
        filas += pagina
        print(f"  pagina {numero}: {len(pagina)} filas (acumulado {len(filas)})")
        if len(pagina) < PAGINA:
            return filas


def detectar_hueco(fecha_min: str) -> str | None:
    """DQ12: devuelve el max de la corrida anterior si min(actual) > max(anterior); None si no hay hueco o no hay corrida previa."""
    previas = [e for e in leer_manifiesto(FUENTE) if e["estado"] == "ok" and e.get("fecha_max")]
    if not previas:
        return None
    anterior = previas[-1]["fecha_max"]
    return anterior if fecha_min > anterior else None


def main() -> int:
    domain = load_config()["domain"]
    count_inicio = contar(domain)
    filas = descargar(domain)
    count_fin = contar(domain)
    if not filas:
        print("ERROR: el dataset devolvio 0 filas", file=sys.stderr)
        return 1

    fechas = [f[CAMPO_FECHA] for f in filas if f.get(CAMPO_FECHA)]
    fecha_min, fecha_max = min(fechas), max(fechas)
    anterior = detectar_hueco(fecha_min)
    extra = {"fecha_min": fecha_min, "fecha_max": fecha_max, "count_inicio": count_inicio, "count_fin": count_fin,
             "hueco": anterior is not None, "max_corrida_anterior": anterior,
             "filas_sin_fecha": len(filas) - len(fechas)}
    ruta = write_raw(FUENTE, datetime.fromisoformat(fecha_min), datetime.fromisoformat(fecha_max),
                     json.dumps(filas, ensure_ascii=False).encode("utf-8"), f"https://{domain}/resource/{DATASET_ID}.json",
                     {"$order": ":id", "$limit": PAGINA}, filas=len(filas), extra=extra)
    print(f"{len(filas)} filas (count {count_inicio} al inicio, {count_fin} al final); {CAMPO_FECHA} {fecha_min} a {fecha_max}; "
          f"archivo: {ruta or 'omitido (misma ventana ya guardada hoy)'}")

    if anterior is not None:
        print(f"HUECO (DQ12): la corrida anterior llego hasta {anterior} y esta empieza en {fecha_min}. "
              "Hay observaciones que ya no estan en la fuente y no se pueden recuperar. Revise las corridas fallidas o retrasadas "
              "del workflow y acorte el intervalo del cron.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
