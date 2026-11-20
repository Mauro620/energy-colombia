"""Aplana data/raw (JSON/CSV comprimidos) a CSV en data/stage, uno por tabla de staging.

Solo aplana: no convierte tipos, no filtra y no cruza. Todo valor sale tal cual como texto; lo vacio queda vacio
(se carga como NULL). Casts, normalizacion y cruces se hacen en SQL (sql/03_carga). Los periodos son los de D07-rev.
"""
import csv
import gzip
import io
import json
import time
from collections.abc import Callable, Iterator
from datetime import date
from pathlib import Path

from pipeline.common import ROOT, RAW
from pipeline.common_raw import leer_manifiesto

STAGE = Path(ROOT / "data" / "stage")
E1_DESDE, E1_HASTA = date(2025, 1, 1), date(2026, 10, 31)
GEN_HORARIA_DESDE = date(2026, 5, 1)


def entradas(fuente: str, desde: date | None = None, hasta: date | None = None) -> list[dict]:
    """Ultima extraccion ok de cada ventana cuya ventana cae dentro de [desde, hasta] (D07-rev)."""
    ultimas: dict[tuple[str, str], dict] = {}
    for e in leer_manifiesto(fuente):
        if e["estado"] == "ok":
            ultimas[(e["ventana_inicio"], e["ventana_fin"])] = e
    elegidas = [e for e in ultimas.values()
                if (desde is None or e["ventana_inicio"][:10] >= desde.isoformat())
                and (hasta is None or e["ventana_fin"][:10] <= hasta.isoformat())]
    return sorted(elegidas, key=lambda e: e["ventana_inicio"])


def _leer(entrada: dict) -> bytes:
    return gzip.decompress((RAW / entrada["archivo"]).read_bytes())


def _simem(entrada: dict) -> Iterator[dict]:
    yield from json.loads(_leer(entrada))["result"]["records"]


def _listado(entrada: dict) -> Iterator[dict]:
    for item in json.loads(_leer(entrada))["Items"]:
        for entidad in item["ListEntities"]:
            yield entidad["Values"]


def _capacidad(entrada: dict) -> Iterator[dict]:
    for item in json.loads(_leer(entrada))["Items"]:
        for d in item["DailyEntities"]:
            yield {"fecha": item["Date"], "codigo": d["Code"], "valor": d["Value"]}


def _json_lista(entrada: dict) -> Iterator[dict]:
    yield from json.loads(_leer(entrada))


def _csv(entrada: dict) -> Iterator[dict]:
    yield from csv.DictReader(io.StringIO(_leer(entrada).decode("utf-8")))


def escribir(nombre: str, columnas: list[str], origen: list[dict], lector: Callable[[dict], Iterator[dict]]) -> int:
    """Escribe data/stage/<nombre>.csv con columnas + archivo_origen + fila_origen. Devuelve las filas escritas."""
    STAGE.mkdir(parents=True, exist_ok=True)
    total = 0
    with (STAGE / f"{nombre}.csv").open("w", newline="", encoding="utf-8") as fh:
        escritor = csv.writer(fh, lineterminator="\n")
        escritor.writerow(columnas + ["archivo_origen", "fila_origen"])
        for entrada in origen:
            for n, fila in enumerate(lector(entrada), start=1):
                escritor.writerow([fila.get(c, "") for c in columnas] + [entrada["archivo"], n])
                total += 1
    return total


def main() -> None:
    ultimo = lambda f: [e for e in [max(entradas(f), key=lambda e: e["extraido_en"], default=None)] if e]  # noqa: E731
    trabajos = [
        ("listado_recursos", ["Code", "Name", "Type", "Disp", "RecType", "CompanyCode", "EnerSource", "OperStartdate", "State"],
         ultimo("xm_ListadoRecursos"), _listado),
        ("agente", ["Code", "Name", "Activity", "OperStartdate", "State"], ultimo("xm_ListadoAgentes"), _listado),
        ("capacidad", ["fecha", "codigo", "valor"], entradas("xm_CapEfecNeta", E1_DESDE, E1_HASTA), _capacidad),
        ("gen_diaria", ["Fecha", "CodigoPlanta", "TipoGeneracion", "TipoClasificacion", "TipoDespachoRecurso", "GeneracionRealEstimada",
                        "GeneracionProgramadaDespacho", "GeneracionProgramadaRedespacho"],
         entradas("simem_E17D25", E1_DESDE, E1_HASTA), _simem),
        ("gen_horaria", ["CodigoVariable", "FechaHora", "CodigoDuracion", "UnidadMedida", "CodigoSICAgente", "CodigoPlanta", "Version", "Valor"],
         entradas("simem_055A4D", GEN_HORARIA_DESDE, E1_HASTA), _simem),
        ("divipola_dpto", ["codigo_departamento", "nombre_departamento", "longitud", "latitud"], ultimo("divipola_vcjz-niiq"), _csv),
        ("divipola_mpio", ["cod_dpto", "dpto", "cod_mpio", "nom_mpio", "tipo_municipio", "longitud", "latitud"], ultimo("divipola_gdxc-w37w"), _csv),
        ("estacion", ["codigo", "nombre", "categoria", "tecnologia", "estado", "departamento", "municipio", "altitud", "longitud", "latitud",
                      "fecha_instalacion", "area_operativa", "corriente", "area_hidrografica", "zona_hidrografica", "subzona_hidrografica",
                      "entidad", "fecha_suspension"], ultimo("socrata_hp9r-jxuu"), _json_lista),
        ("observacion", ["codigoestacion", "codigosensor", "fechaobservacion", "valorobservado", "descripcionsensor", "unidadmedida"],
         entradas("ideam_observaciones"), _json_lista),
        ("upme", ["ano", "mes", "fuente", "promedio_mensual_gwh", "maximo_gwh", "minimo_gwh", "generacion_total_gwh", "porcentaje_participacion"],
         ultimo("socrata_tq63-itzr"), _json_lista),
    ]
    for nombre, columnas, origen, lector in trabajos:
        t0 = time.monotonic()
        filas = escribir(nombre, columnas, origen, lector)
        print(f"{nombre}: {filas} filas de {len(origen)} archivos, {time.monotonic() - t0:.1f} s")


if __name__ == "__main__":
    main()
