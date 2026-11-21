import os
from pathlib import Path

import requests
import yaml
from dotenv import load_dotenv
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

ROOT = Path(__file__).resolve().parents[1]
RAW = Path(os.getenv("ENERGIA_RAW_DIR", ROOT / "data" / "raw"))  # la variable permite probar sin tocar data/raw real
SAMPLE = ROOT / "data" / "sample"
FUENTES = ROOT / "docs" / "fuentes"
CATALOGO = FUENTES / "catalogo"
PERFILES = FUENTES / "perfiles"
TIMEOUT = 120


def load_config() -> dict:
    return yaml.safe_load((ROOT / "pipeline" / "config.yaml").read_text(encoding="utf-8"))


def new_session() -> requests.Session:
    """Sesion con reintentos y espera exponencial (1s, 2s, 4s, 8s, 16s) ante 429/5xx."""
    load_dotenv(ROOT / ".env")
    retry = Retry(
        total=5,
        backoff_factor=1,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET",),
    )
    session = requests.Session()
    session.mount("https://", HTTPAdapter(max_retries=retry))
    token = os.getenv("SOCRATA_APP_TOKEN")
    if token:
        session.headers["X-App-Token"] = token
    return session
