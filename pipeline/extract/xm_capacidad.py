"""Capacidad Efectiva Neta por recurso (CapEfecNeta, kW, diaria) de la API XM, en ventanas de <= 30 dias, reanudable (D13)."""
import argparse
import time
from datetime import date

from pipeline.common_raw import registrar_error, solicitar, ventanas_pendientes, write_raw

URL = "https://servapibi.xm.com.co/daily"
METRICA = "CapEfecNeta"
FUENTE = f"xm_{METRICA}"
MAX_DIAS = 30  # MaxDays de la metrica es 31 (ListadoMetricas)


def extraer_ventana(inicio: date, fin: date) -> dict:
    body = {"MetricId": METRICA, "Entity": "Recurso", "StartDate": inicio.isoformat(), "EndDate": fin.isoformat()}
    try:
        response = solicitar("POST", URL, json_body=body, timeout=180)
        items = response.json()["Items"]
        fechas = sorted({i["Date"] for i in items})
        ruta = write_raw(FUENTE, inicio, fin, response.content, URL, body, filas=len(items),
                         extra={"dias_con_datos": len(fechas), "fecha_min": fechas[0] if fechas else None,
                                "fecha_max": fechas[-1] if fechas else None})
        return {"ok": True, "filas": len(items), "bytes": ruta.stat().st_size if ruta else 0, "dias": len(fechas)}
    except Exception as exc:  # DQ13: queda pendiente y se sigue
        registrar_error(FUENTE, inicio, fin, URL, body, repr(exc))
        print(f"  ERROR {inicio}..{fin}: {exc!r}")
        return {"ok": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desde", type=date.fromisoformat, default=date(2025, 1, 1))
    parser.add_argument("--hasta", type=date.fromisoformat, default=date(2026, 10, 31))
    args = parser.parse_args()
    pendientes = ventanas_pendientes(FUENTE, args.desde, args.hasta, MAX_DIAS)
    print(f"{FUENTE}: {len(pendientes)} ventanas pendientes entre {args.desde} y {args.hasta}")
    t_total, ok, fallidas, filas, bytes_ = time.monotonic(), 0, 0, 0, 0
    for inicio, fin in pendientes:
        t0 = time.monotonic()
        r = extraer_ventana(inicio, fin)
        if not r["ok"]:
            fallidas += 1
            continue
        ok, filas, bytes_ = ok + 1, filas + r["filas"], bytes_ + r["bytes"]
        print(f"  {inicio}..{fin}: {r['filas']} items, {r['dias']} dias, {r['bytes'] / 1e6:.2f} MB gz, {time.monotonic() - t0:.1f} s")
    print(f"Resumen: {ok} ventanas ok, {fallidas} fallidas, {filas} items, {bytes_ / 1e6:.2f} MB gz, {time.monotonic() - t_total:.1f} s")
    return 1 if fallidas else 0


if __name__ == "__main__":
    raise SystemExit(main())
