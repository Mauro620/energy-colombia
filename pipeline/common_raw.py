"""Aterrizaje crudo e inmutable (D03): data/raw/<fuente>/<fecha extraccion>/<inicio>_<fin>.json.gz + manifest.jsonl."""
import gzip
import hashlib
import json
import os
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import requests

from pipeline.common import RAW

INTENTOS = 3
ESPERA_BASE = 2.0  # segundos: 2, 4 entre intentos
TIMEOUT = 120


def solicitar(
    method: str, url: str, *, params: dict | None = None, json_body: dict | None = None,
    timeout: int = TIMEOUT, intentos: int = INTENTOS, espera: float = ESPERA_BASE, headers: dict | None = None,
) -> requests.Response:
    """HTTP con timeout y reintentos con espera exponencial ante errores de red, 429 y 5xx (DQ01)."""
    for intento in range(1, intentos + 1):
        try:
            response = requests.request(method, url, params=params, json=json_body, timeout=timeout, headers=headers)
            if response.status_code != 429 and response.status_code < 500:
                response.raise_for_status()
                return response
            error: Exception = requests.HTTPError(f"HTTP {response.status_code}", response=response)
        except (requests.ConnectionError, requests.Timeout) as exc:
            error = exc
        if intento == intentos:
            raise error
        time.sleep(espera * 2 ** (intento - 1))
    raise AssertionError("inalcanzable")


def ruta_manifiesto(fuente: str) -> Path:
    return RAW / fuente / "manifest.jsonl"


def leer_manifiesto(fuente: str) -> list[dict]:
    path = ruta_manifiesto(fuente)
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _agregar_al_manifiesto(fuente: str, entrada: dict) -> None:
    path = ruta_manifiesto(fuente)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entrada, ensure_ascii=False, sort_keys=True) + "\n")
        fh.flush()
        os.fsync(fh.fileno())


def _ahora_utc() -> datetime:
    return datetime.now(timezone.utc)


def _en_nombre(v: date | datetime) -> str:
    """Fecha ISO, o fecha-hora sin ':' (los artefactos de GitHub Actions no admiten ':' en nombres)."""
    return v.strftime("%Y-%m-%dT%H%M%S") if isinstance(v, datetime) else v.isoformat()


def _base_entrada(fuente: str, inicio: date, fin: date, url: str, params: dict | None) -> dict:
    return {
        "fuente": fuente, "ventana_inicio": inicio.isoformat(), "ventana_fin": fin.isoformat(),
        "url": url, "params": params or {}, "extraido_en": _ahora_utc().isoformat(),
    }


def write_raw(
    fuente: str, ventana_inicio: date | datetime, ventana_fin: date | datetime, payload: bytes | object, url: str,
    params: dict | None, filas: int | None = None, extra: dict | None = None,
) -> Path | None:
    """Guarda la respuesta comprimida sin sobrescribir nunca. Devuelve la ruta, o None si ya existia (se registra como omitido).

    `payload` ideal: los bytes de la respuesta tal cual. Un objeto se serializa a JSON.
    """
    contenido = payload if isinstance(payload, bytes) else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    comprimido = gzip.compress(contenido, mtime=0)  # mtime=0: mismo contenido, mismo hash
    carpeta = RAW / fuente / _ahora_utc().strftime("%Y-%m-%d")
    destino = carpeta / f"{_en_nombre(ventana_inicio)}_{_en_nombre(ventana_fin)}.json.gz"
    entrada = _base_entrada(fuente, ventana_inicio, ventana_fin, url, params) | (extra or {})
    entrada["archivo"] = str(destino.relative_to(RAW))

    if destino.exists():
        entrada.update(estado="omitido_existente", filas=filas, bytes=destino.stat().st_size,
                       sha256=hashlib.sha256(destino.read_bytes()).hexdigest())
        _agregar_al_manifiesto(fuente, entrada)
        return None

    carpeta.mkdir(parents=True, exist_ok=True)
    temporal = destino.with_name(destino.name + ".tmp")
    temporal.write_bytes(comprimido)
    try:
        os.link(temporal, destino)  # falla si destino existe: nunca pisa un archivo
    finally:
        temporal.unlink()
    entrada.update(estado="ok", filas=filas, bytes=len(comprimido), sha256=hashlib.sha256(comprimido).hexdigest(),
                   sha256_contenido=hashlib.sha256(contenido).hexdigest())
    _agregar_al_manifiesto(fuente, entrada)
    return destino


def registrar_error(fuente: str, inicio: date, fin: date, url: str, params: dict | None, error: str) -> None:
    """DQ13: la ventana que falla queda registrada y seguira pendiente."""
    _agregar_al_manifiesto(fuente, _base_entrada(fuente, inicio, fin, url, params) | {"estado": "error", "error": error[:300]})


def ventanas_pendientes(fuente: str, desde: date, hasta: date, dias: int = 30) -> list[tuple[date, date]]:
    """Ventanas consecutivas de hasta `dias` dias entre desde y hasta que aun no tienen estado ok en el manifiesto."""
    hechas = {(e["ventana_inicio"], e["ventana_fin"]) for e in leer_manifiesto(fuente) if e["estado"] == "ok"}
    pendientes, inicio = [], desde
    while inicio <= hasta:
        fin = min(inicio + timedelta(days=dias - 1), hasta)
        if (inicio.isoformat(), fin.isoformat()) not in hechas:
            pendientes.append((inicio, fin))
        inicio = fin + timedelta(days=1)
    return pendientes


def leer_payload(fuente: str, inicio: date, fin: date) -> bytes | None:
    """Contenido descomprimido de la ultima extraccion ok de esa ventana, o None."""
    ok = [e for e in leer_manifiesto(fuente) if e["estado"] == "ok"
          and (e["ventana_inicio"], e["ventana_fin"]) == (inicio.isoformat(), fin.isoformat())]
    return gzip.decompress((RAW / ok[-1]["archivo"]).read_bytes()) if ok else None


def escribir_una_vez(path: Path, texto: str) -> bool:
    """Para archivos crudos sueltos (metadata, muestras): no sobrescribe. False si ya existia."""
    if path.exists():
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as fh:
        fh.write(texto)
    return True


def ultimo_ok(fuente: str) -> dict | None:
    ok = [e for e in leer_manifiesto(fuente) if e["estado"] == "ok"]
    return ok[-1] if ok else None


def verificar_manifiestos() -> dict[str, dict[str, int]]:
    """Por fuente: entradas ok cuyo sha256 coincide con el archivo, que no coinciden, sin archivo, y archivos en disco sin entrada ok (D03)."""
    resultado = {}
    for manifiesto in sorted(RAW.glob("*/manifest.jsonl")):
        fuente = manifiesto.parent.name
        ok = [e for e in leer_manifiesto(fuente) if e["estado"] == "ok"]
        cuenta = {"coinciden": 0, "no_coinciden": 0, "sin_archivo": 0}
        for e in ok:
            archivo = RAW / e["archivo"]
            if not archivo.exists():
                cuenta["sin_archivo"] += 1
            elif hashlib.sha256(archivo.read_bytes()).hexdigest() == e["sha256"]:
                cuenta["coinciden"] += 1
            else:
                cuenta["no_coinciden"] += 1
        en_disco = {str(p.relative_to(RAW)) for p in manifiesto.parent.rglob("*.json.gz")}
        cuenta["en_disco_sin_entrada"] = len(en_disco - {e["archivo"] for e in ok})
        resultado[fuente] = cuenta
    return resultado


if __name__ == "__main__":  # python -m pipeline.common_raw: verifica que los manifiestos cuadren con el disco
    resultado = verificar_manifiestos()
    for fuente, c in resultado.items():
        print(f"{fuente}: {c}")
    raise SystemExit(0 if all(c["no_coinciden"] == c["sin_archivo"] == c["en_disco_sin_entrada"] == 0 for c in resultado.values()) else 1)
