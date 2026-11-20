"""DIVIPOLA del DANE en datos.gov.co: descubre por el catalogo Socrata los datasets de departamentos y municipios y guarda su CSV (D05)."""
import sys
from datetime import datetime, timezone

from pipeline.common import load_config
from pipeline.common_raw import solicitar, ventanas_pendientes, write_raw

CATALOGO = "https://api.us.socrata.com/api/catalog/v1"
COLUMNAS_ESPERADAS = {
    "departamentos": {"Código Departamento", "Nombre Departamento"},
    "municipios": {"Código Departamento", "Código Municipio", "Nombre Municipio"},
}


def descubrir(domain: str) -> dict[str, dict]:
    """Datasets tabulares del DANE cuyo nombre es 'DIVIPOLA- Códigos <departamentos|municipios>' y cuyas columnas incluyen los codigos."""
    resultados = solicitar("GET", CATALOGO, params={"domains": domain, "q": "divipola", "limit": 50}).json()["results"]
    encontrados = {}
    for r in resultados:
        recurso = r["resource"]
        nombre = recurso["name"].strip().lower()
        if recurso["type"] != "dataset" or "estad" not in (recurso.get("attribution") or "").lower():
            continue
        for clave, columnas in COLUMNAS_ESPERADAS.items():
            if nombre == f"divipola- códigos {clave}" and columnas <= set(recurso["columns_name"]):
                encontrados[clave] = {"id": recurso["id"], "nombre": recurso["name"], "columnas": recurso["columns_name"]}
    return encontrados


def main() -> int:
    domain = load_config()["domain"]
    encontrados = descubrir(domain)
    faltan = set(COLUMNAS_ESPERADAS) - set(encontrados)
    if faltan:
        print(f"DETENIDO: no se encontro DIVIPOLA del DANE para {sorted(faltan)} en {domain}", file=sys.stderr)
        return 1
    hoy = datetime.now(timezone.utc).date()
    for clave, ds in encontrados.items():
        fuente = f"divipola_{ds['id']}"
        print(f"{clave}: {ds['id']} '{ds['nombre']}' columnas {ds['columnas']}")
        if not ventanas_pendientes(fuente, hoy, hoy):
            print(f"  {fuente}: {hoy} ya esta en el manifiesto")
            continue
        url = f"https://{domain}/resource/{ds['id']}.csv"
        params = {"$limit": 50000, "$order": ":id"}
        contenido = solicitar("GET", url, params=params).content
        filas = contenido.decode("utf-8").count("\n") - 1
        ruta = write_raw(fuente, hoy, hoy, contenido, url, params, filas=filas)
        print(f"  {fuente}: {filas} filas -> {ruta or 'omitido'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
