"""ListadoAgentes de la API XM (agentes registrados ante el ASIC): maestro de operadores."""
import json
from datetime import datetime, timezone

import pandas as pd

from pipeline.common_raw import leer_payload
from pipeline.extract.xm_listados import extraer

METRICA = "ListadoAgentes"


def main() -> None:
    hoy = datetime.now(timezone.utc).date()
    fuente = extraer(METRICA, hoy)
    items = json.loads(leer_payload(fuente, hoy, hoy))["Items"]
    df = pd.DataFrame([e["Values"] for i in items for e in i["ListEntities"]])
    print(f"{METRICA}: {len(df)} filas, columnas {list(df.columns)}")
    print(df.head(3).to_string())


if __name__ == "__main__":
    main()
