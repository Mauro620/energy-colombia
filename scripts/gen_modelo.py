"""Genera desde docs/modelo/modelo_er.dbml: modelo_er.mmd (Mermaid), modelo_er.dot y diccionario.md.

Uso (stdlib pura):  python scripts/gen_modelo.py
Imagen:  docker run --rm -v "$PWD/docs/modelo:/m" energia-dot dot -Tsvg /m/modelo_er.dot -o /m/modelo_er.svg  (idem -Tpng)
"""
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELO = ROOT / "docs" / "modelo"
ESQUEMAS_DIAGRAMA = ("energia", "control")  # staging no tiene relaciones: se documenta pero no se dibuja


@dataclass
class Columna:
    nombre: str
    tipo: str
    pk: bool = False
    not_null: bool = False
    unique: bool = False
    ref: str | None = None  # "esquema.tabla.columna"
    src: str = "-"
    regla: str = ""


@dataclass
class Tabla:
    nombre: str  # esquema.tabla
    columnas: list[Columna] = field(default_factory=list)
    pk_compuesta: list[str] = field(default_factory=list)
    nota: str = ""


def _dividir(settings: str) -> list[str]:
    """Separa por comas fuera de comillas."""
    partes, actual, comilla = [], "", False
    for ch in settings:
        if ch == "'":
            comilla = not comilla
        if ch == "," and not comilla:
            partes.append(actual.strip())
            actual = ""
        else:
            actual += ch
    return partes + [actual.strip()] if actual.strip() else partes


def parsear(texto: str) -> tuple[dict[str, Tabla], dict[str, list[str]]]:
    tablas: dict[str, Tabla] = {}
    enums: dict[str, list[str]] = {}
    lineas = texto.splitlines()
    i = 0
    while i < len(lineas):
        m = re.match(r"^(Table|Enum)\s+([\w.]+)\s*\{", lineas[i])
        if not m:
            i += 1
            continue
        tipo, nombre = m.groups()
        cuerpo = []
        i += 1
        while not lineas[i].startswith("}"):
            cuerpo.append(lineas[i])
            i += 1
        if tipo == "Enum":
            enums[nombre] = [v.strip().strip('"') for v in cuerpo if v.strip() and not v.strip().startswith("//")]
        else:
            tablas[nombre] = _parsear_tabla(nombre, cuerpo)
        i += 1
    return tablas, enums


def _parsear_tabla(nombre: str, cuerpo: list[str]) -> Tabla:
    tabla, dentro_indexes = Tabla(nombre), False
    for linea in cuerpo:
        s = linea.strip()
        if s.startswith("indexes {"):
            dentro_indexes = True
            continue
        if dentro_indexes:
            if s == "}":
                dentro_indexes = False
            else:
                mpk = re.match(r"\(([^)]*)\)\s*\[pk", s)
                if mpk:
                    tabla.pk_compuesta = [c.strip() for c in mpk.group(1).split(",")]
            continue
        if s.startswith("Note:"):
            tabla.nota = re.search(r"'(.*)'", s).group(1)
            continue
        m = re.match(r"^(\w+)\s+([\w.]+(?:\([\d, ]+\))?(?:\[\])?)(?:\s+\[(.*)\])?\s*$", s)
        if not m or s.startswith("//"):
            continue
        col = Columna(m.group(1), m.group(2))
        for ajuste in _dividir(m.group(3) or ""):
            if ajuste == "pk":
                col.pk = col.not_null = True
            elif ajuste == "not null":
                col.not_null = True
            elif ajuste == "unique":
                col.unique = True
            elif ajuste.startswith("ref:"):
                col.ref = ajuste.split(">")[1].strip()
            elif ajuste.startswith("note:"):
                nota = re.search(r"'(.*)'", ajuste).group(1)
                src, _, regla = nota.partition(" || rule=")
                col.src = src.removeprefix("src=").strip() or "-"
                col.regla = regla.strip()
        tabla.columnas.append(col)
    for nombre_col in tabla.pk_compuesta:
        for c in tabla.columnas:
            if c.nombre == nombre_col:
                c.pk = c.not_null = True
    return tabla


def _id_mermaid(nombre: str) -> str:
    return nombre.replace(".", "_")


def mermaid(tablas: dict[str, Tabla]) -> str:
    visibles = {n: t for n, t in tablas.items() if n.split(".")[0] in ESQUEMAS_DIAGRAMA}
    lineas = ["erDiagram"]
    for nombre, t in visibles.items():
        lineas.append(f"  {_id_mermaid(nombre)} {{")
        for c in t.columnas:
            tipo = re.sub(r"[(), .]+", "_", c.tipo).strip("_")
            marca = "PK" if c.pk and c.ref is None else "FK" if c.ref else "UK" if c.unique else ""
            lineas.append(f"    {tipo} {c.nombre} {marca}".rstrip())
        lineas.append("  }")
    for nombre, t in visibles.items():
        for c in t.columnas:
            if c.ref:
                padre = ".".join(c.ref.split(".")[:2])
                cardinalidad = "}o--||" if c.not_null else "}o--o|"
                lineas.append(f"  {_id_mermaid(nombre)} {cardinalidad} {_id_mermaid(padre)} : \"{c.nombre}\"")
    return "\n".join(lineas) + "\n"


COLORES = {"energia": "#dbeafe", "control": "#fef3c7"}


def dot(tablas: dict[str, Tabla]) -> str:
    visibles = {n: t for n, t in tablas.items() if n.split(".")[0] in ESQUEMAS_DIAGRAMA}
    salida = ['digraph ER {', '  rankdir=LR; nodesep=0.35; ranksep=1.1; splines=true;',
              '  node [shape=plain, fontname="DejaVu Sans", fontsize=10]; edge [color="#475569", dir=both, arrowtail=crow, arrowhead=tee, fontsize=8];']
    for nombre, t in visibles.items():
        color = COLORES[nombre.split(".")[0]]
        filas = [f'<TR><TD BGCOLOR="{color}" COLSPAN="2"><B>{nombre}</B></TD></TR>']
        for c in t.columnas:
            marca = "PK " if c.pk else ""
            fk = " (FK)" if c.ref else ""
            filas.append(f'<TR><TD ALIGN="LEFT" PORT="{c.nombre}">{marca}{c.nombre}{fk}</TD><TD ALIGN="LEFT"><FONT COLOR="#64748b">{c.tipo}</FONT></TD></TR>')
        salida.append(f'  "{nombre}" [label=<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="3">{"".join(filas)}</TABLE>>];')
    for nombre, t in visibles.items():
        for c in t.columnas:
            if c.ref:
                padre = ".".join(c.ref.split(".")[:2])
                salida.append(f'  "{nombre}":"{c.nombre}" -> "{padre}" [label="{c.nombre}"];')
    salida.append("}")
    return "\n".join(salida) + "\n"


def diccionario(tablas: dict[str, Tabla], enums: dict[str, list[str]]) -> str:
    lineas = ["# Diccionario de datos (E1)", "",
              "_Generado por `scripts/gen_modelo.py` desde `modelo_er.dbml`. No editar a mano: editar el DBML y regenerar._", "",
              "Columnas: **tabla**, **columna**, **tipo**, **nulos** (Si = admite NULL), **regla** (restricciones y codigo RNxx de `sql/02_reglas`), "
              "**origen** (`fuente.columna`; las fuentes estan en `docs/fuentes` y `data/raw`). `-` = surrogate o derivada.", ""]
    for esquema in ("energia", "control", "staging"):
        lineas += [f"## Esquema `{esquema}`", "", "| Tabla | Columna | Tipo | Nulos | Regla | Origen (fuente.columna) |", "|---|---|---|---|---|---|"]
        for nombre, t in tablas.items():
            if not nombre.startswith(esquema + "."):
                continue
            for c in t.columnas:
                claves = [k for k, v in (("PK", c.pk), ("UNIQUE", c.unique)) if v] + ([f"FK -> {c.ref}"] if c.ref else [])
                regla = "; ".join(claves + ([c.regla] if c.regla else []))
                lineas.append(f"| {nombre.split('.')[1]} | {c.nombre} | {c.tipo} | {'No' if c.not_null else 'Si'} | {regla.replace('|', '/')} | {c.src.replace('|', '/')} |")
        lineas.append("")
        notas = [(n, t.nota) for n, t in tablas.items() if n.startswith(esquema + ".") and t.nota]
        lineas += [f"- **{n}**: {nota}" for n, nota in notas] + ([""] if notas else [])
    lineas += ["## Tipos ENUM", "", "| Tipo | Valores |", "|---|---|"]
    lineas += [f"| {n} | {', '.join(v)} |" for n, v in enums.items()]
    fragmento = MODELO / "3fn_redundancias.md"
    if fragmento.exists():
        lineas += ["", fragmento.read_text(encoding="utf-8").rstrip(), ""]
    return "\n".join(lineas) + "\n"


def main() -> int:
    tablas, enums = parsear((MODELO / "modelo_er.dbml").read_text(encoding="utf-8"))
    (MODELO / "modelo_er.mmd").write_text(mermaid(tablas), encoding="utf-8")
    (MODELO / "modelo_er.dot").write_text(dot(tablas), encoding="utf-8")
    (MODELO / "diccionario.md").write_text(diccionario(tablas, enums), encoding="utf-8")
    n_cols = sum(len(t.columnas) for t in tablas.values())
    print(f"{len(tablas)} tablas, {n_cols} columnas, {len(enums)} enums, {sum(1 for t in tablas.values() for c in t.columnas if c.ref)} FK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
