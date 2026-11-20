"""Backfill de SIMEM por ventanas de hasta 30 dias, reanudable: solo extrae lo que el manifiesto no tiene con estado ok.

Por defecto usa F01 (E17D25), la unica fuente de generacion segun D02. Ejemplo (solo enero):
    python -m pipeline.extract.simem_backfill --desde 2025-01-01 --hasta 2025-01-31
"""
import argparse
import time
from datetime import date

from pipeline.common_raw import registrar_error, solicitar, ventanas_pendientes, write_raw
from pipeline.extract.simem_explorar import URL

PERIODO_INICIO, PERIODO_FIN = date(2025, 1, 1), date(2026, 10, 31)  # D07


def extraer_ventana(dataset_id: str, inicio: date, fin: date) -> dict:
    fuente = f"simem_{dataset_id}"
    params = {"datasetId": dataset_id, "startDate": inicio.isoformat(), "endDate": fin.isoformat()}
    try:
        response = solicitar("GET", URL, params=params)
        cuerpo = response.json()
        resultado = cuerpo["result"]
        if not cuerpo["success"] or resultado["idDataset"] != dataset_id:
            raise ValueError(f"respuesta inesperada: success={cuerpo['success']}, idDataset={resultado.get('idDataset')}")
        registros = resultado["records"]
        fechas = sorted({r[resultado["filterDate"]][:10] for r in registros})
        ruta = write_raw(fuente, inicio, fin, response.content, URL, params, filas=len(registros),
                         extra={"dias_con_datos": len(fechas), "fecha_min": fechas[0] if fechas else None,
                                "fecha_max": fechas[-1] if fechas else None})
        return {"ok": True, "filas": len(registros), "bytes": ruta.stat().st_size if ruta else 0, "dias_con_datos": len(fechas)}
    except Exception as exc:  # DQ13: la ventana queda registrada como pendiente y se sigue con la siguiente
        registrar_error(fuente, inicio, fin, URL, params, repr(exc))
        print(f"  ERROR {inicio}..{fin}: {exc!r}")
        return {"ok": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dataset", default="E17D25", help="datasetId de SIMEM (por defecto F01)")
    parser.add_argument("--desde", type=date.fromisoformat, default=PERIODO_INICIO)
    parser.add_argument("--hasta", type=date.fromisoformat, default=PERIODO_FIN)
    parser.add_argument("--dias", type=int, default=30, help="tamano de ventana (maximo 30, DQ13)")
    args = parser.parse_args()
    if not 1 <= args.dias <= 30:
        parser.error("--dias debe estar entre 1 y 30")

    fuente = f"simem_{args.dataset}"
    pendientes = ventanas_pendientes(fuente, args.desde, args.hasta, args.dias)
    print(f"{fuente}: {len(pendientes)} ventanas pendientes entre {args.desde} y {args.hasta}")
    inicio_total, ok, fallidas, filas, bytes_, dias = time.monotonic(), 0, 0, 0, 0, 0
    for inicio, fin in pendientes:
        t0 = time.monotonic()
        r = extraer_ventana(args.dataset, inicio, fin)
        if not r["ok"]:
            fallidas += 1
            continue
        ok, filas, bytes_, dias = ok + 1, filas + r["filas"], bytes_ + r["bytes"], dias + (fin - inicio).days + 1
        print(f"  {inicio}..{fin}: {r['filas']} filas, {r['dias_con_datos']} dias con datos, {r['bytes'] / 1e6:.2f} MB gz, {time.monotonic() - t0:.1f} s")
    segundos = time.monotonic() - inicio_total

    print(f"Resumen: {ok} ventanas ok, {fallidas} fallidas, {filas} filas, {bytes_ / 1e6:.2f} MB gz, {segundos:.1f} s")
    if dias:
        total_dias = (PERIODO_FIN - PERIODO_INICIO).days + 1
        factor = total_dias / dias
        print(f"Proyeccion al periodo {PERIODO_INICIO}..{PERIODO_FIN} ({total_dias} dias, a partir de {dias} dias medidos): "
              f"{filas * factor:,.0f} filas, {bytes_ * factor / 1e6:,.0f} MB gz, {segundos * factor / 60:,.1f} min")
    return 1 if fallidas else 0


if __name__ == "__main__":
    raise SystemExit(main())
