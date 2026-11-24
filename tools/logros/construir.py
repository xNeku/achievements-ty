#!/usr/bin/env python3
"""Construye la base de datos de logros de Hangar.

Fuentes (cada una es opcional):
  --xbox DIR        volcado JSON de Xbox 360 / Xbox One (prashantkhandelwal/XBoxAchievements, carpeta Data)
  RA_API_KEY        clave de la Web API de RetroAchievements: listas de logros de N64, PS1, PS2, GameCube…
  --ra-todo         con RA_API_KEY, baja TODOS los juegos con logros de RetroAchievements (tarda horas),
                    no solo los que están en nuestros catálogos

Salidas:
  OUT/logros.db                 SQLite con todos los juegos y logros de todas las fuentes
  data/logros/<cat>/<id>.json   la lista de logros de cada juego de nuestros catálogos (lo que lee la app)
  data/juegos*.json             cada juego enlazado recibe "logros": [{fuente, total, puntos}]

Solo se guardan los datos de los logros (nombre, descripción, puntos, icono). No se vincula ninguna cuenta.
"""

import argparse
import base64
import difflib
import io
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # sin Pillow los logros de Xbox van sin icono
    Image = None

RA = "https://retroachievements.org/API/"
RA_KEY = os.environ.get("RA_API_KEY", "")
RA_BADGE = "https://media.retroachievements.org/Badge/{}.png"
CACHE_RA = Path("data/logros/cache-retroachievements.json")

# Nuestro "origen" interno -> nombres de consola de RetroAchievements
RA_CONSOLAS = {
    "n64": ["nintendo 64"], "snes": ["snes", "super nintendo entertainment system"], "nes": ["nes", "nintendo entertainment system"],
    "gb": ["game boy"], "gbc": ["game boy color"], "gba": ["game boy advance"], "ds": ["nintendo ds"],
    "genesis": ["genesis/mega drive", "mega drive", "genesis"], "32x": ["32x"], "mastersystem": ["master system"],
    "ps1": ["playstation"], "ps2": ["playstation 2"], "psp": ["playstation portable"], "gamecube": ["gamecube"],
    "wii": ["wii"], "dreamcast": ["dreamcast"], "saturn": ["saturn"], "arcade": ["arcade"], "amiga": ["amiga"], "dos": ["dos", "ms-dos"],
}


ROMANOS = {"ii": "2", "iii": "3", "iv": "4", "vi": "6", "vii": "7", "viii": "8", "ix": "9", "xi": "11", "xii": "12", "xiii": "13"}


def numeros(s):
    """Los números de un título (Storm 3 ≠ Storm 4), con los romanos pasados a cifras."""
    t = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    t = re.sub(r"[\(\[][^\)\]]*[\)\]]", " ", t)
    return sorted(ROMANOS.get(w, w) for w in re.findall(r"[a-z0-9]+", t) if w.isdigit() or w in ROMANOS)


def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\b(" + "|".join(sorted(ROMANOS, key=len, reverse=True)) + r")\b", lambda m: ROMANOS[m.group(1)], s)
    s = re.sub(r"[\(\[][^\)\]]*[\)\]]", " ", s)
    s = re.sub(r"^(.*?),\s*the\b", r"the \1", s)  # "Legend of Zelda, The: ..." -> "the legend of zelda: ..."
    s = s.replace("&", " and ")
    s = re.sub(r"\b(recompiled|recomp|remastered|android|port|native|edition|version)\b", " ", s)
    s = re.sub(r"^the\s+", "", s.strip())
    return re.sub(r"[^a-z0-9]+", "", s)


def mejor(nombre, candidatos, umbral=0.92, nombres=None):
    """candidatos: {norm: valor}. Exacto, o muy parecido y con los mismos números."""
    n = norm(nombre)
    if not n:
        return None, 0
    if n in candidatos:
        return candidatos[n], 1.0
    for m in difflib.get_close_matches(n, list(candidatos), n=3, cutoff=umbral):
        if nombres is not None and numeros(nombre) != numeros(nombres.get(m, "")):
            continue
        return candidatos[m], round(difflib.SequenceMatcher(None, n, m).ratio(), 3)
    return None, 0


def icono_pequeno(b64):
    if not b64 or Image is None:
        return None
    try:
        im = Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGB")
        im.thumbnail((56, 56))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=62, optimize=True)
        return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    except Exception:  # noqa: BLE001
        return None


def esquema(db):
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS juegos (
          id INTEGER PRIMARY KEY, fuente TEXT NOT NULL, fuente_id TEXT NOT NULL, nombre TEXT NOT NULL, norm TEXT,
          consola TEXT, total INTEGER, puntos INTEGER, UNIQUE (fuente, fuente_id));
        CREATE TABLE IF NOT EXISTS logros (
          id INTEGER PRIMARY KEY, juego INTEGER NOT NULL REFERENCES juegos(id), fuente_id TEXT, nombre TEXT, descripcion TEXT,
          puntos INTEGER, icono TEXT, orden INTEGER, tipo TEXT, extra TEXT);
        CREATE TABLE IF NOT EXISTS vinculos (
          catalogo TEXT, juego_catalogo TEXT, juego INTEGER REFERENCES juegos(id), metodo TEXT, confianza REAL);
        CREATE INDEX IF NOT EXISTS logros_juego ON logros(juego);
        CREATE INDEX IF NOT EXISTS juegos_norm ON juegos(norm);
        """
    )


def guardar_juego(db, fuente, fuente_id, nombre, consola, logros):
    cur = db.execute(
        "INSERT OR REPLACE INTO juegos (fuente, fuente_id, nombre, norm, consola, total, puntos) VALUES (?,?,?,?,?,?,?)",
        (fuente, str(fuente_id), nombre, norm(nombre), consola, len(logros), sum(l.get("puntos") or 0 for l in logros)),
    )
    jid = cur.lastrowid
    db.execute("DELETE FROM logros WHERE juego = ?", (jid,))
    db.executemany(
        "INSERT INTO logros (juego, fuente_id, nombre, descripcion, puntos, icono, orden, tipo, extra) VALUES (?,?,?,?,?,?,?,?,?)",
        [(jid, l.get("id"), l["nombre"], l.get("descripcion"), l.get("puntos"), l.get("icono"), i, l.get("tipo"), json.dumps(l["extra"]) if l.get("extra") else None) for i, l in enumerate(logros)],
    )
    return jid


# ───────────────────────── Xbox ─────────────────────────


def cargar_xbox(db, carpeta):
    total = 0
    for sub, fuente in (("XBox360", "xbox360"), ("XBoxOne", "xboxone")):
        d = Path(carpeta) / sub
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.json")):
            try:
                g = json.load(open(f, encoding="utf-8-sig"))
            except Exception:  # noqa: BLE001
                continue
            logros = []
            for a in g.get("Achievements") or []:
                try:
                    pts = int(str(a.get("Gs") or "0").strip() or 0)
                except ValueError:
                    pts = 0
                logros.append({"id": a.get("Id"), "nombre": (a.get("Name") or "").strip(), "descripcion": (a.get("Description") or "").strip(), "puntos": pts, "icono": icono_pequeno(a.get("Image")), "tipo": "secreto" if "secret" in str(a.get("Tags") or "").lower() else None})
            if logros:
                guardar_juego(db, fuente, g.get("Id") or f.stem, (g.get("Name") or f.stem).strip(), fuente, logros)
                total += 1
    db.commit()
    print(f"Xbox: {total} juegos", file=sys.stderr)


# ───────────────────────── RetroAchievements ─────────────────────────


def ra(endpoint, **params):
    params["y"] = RA_KEY
    url = RA + endpoint + "?" + urllib.parse.urlencode(params)
    for intento in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Hangar-logros"}), timeout=60) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            print(f"  RA {endpoint} reintento {intento + 1}: {e}", file=sys.stderr)
            time.sleep(3 * (intento + 1))
    return None


def cargar_ra(db, catalogos, todo=False):
    consolas = ra("API_GetConsoleIDs.php") or []
    # "SNES/Super Famicom", "NES/Famicom", "Genesis/Mega Drive"… valen por cualquiera de sus nombres
    por_nombre = {}
    for c in consolas:
        nombre = c["Name"].lower()
        for alias in [nombre, *nombre.split("/")]:
            por_nombre.setdefault(alias.strip(), c["ID"])
    orig_a_id = {o: next((por_nombre[n] for n in ns if n in por_nombre), None) for o, ns in RA_CONSOLAS.items()}
    # Juegos con logros de cada consola que nos interesa
    listas = {}
    for o, cid in orig_a_id.items():
        if not cid:
            continue
        juegos = ra("API_GetGameList.php", i=cid, f=1) or []
        listas[o] = {norm(g["Title"]): g for g in juegos if not g["Title"].startswith("~") and g.get("NumAchievements")}
        time.sleep(0.4)
    # Qué juegos bajar: los enlazados con el catálogo, o todos
    pedir = {}
    for cat, juegos in catalogos.items():
        for j in juegos:
            o = j.get("origen")
            if o in listas:
                g, conf = mejor(j["nombre"], listas[o], nombres={k: v["Title"] for k, v in listas[o].items()})
                if g:
                    pedir[g["ID"]] = (o, g)
    if todo:
        for o, lst in listas.items():
            for g in lst.values():
                pedir.setdefault(g["ID"], (o, g))
    print(f"RetroAchievements: {len(consolas)} consolas, {sum(len(v) for v in listas.values())} juegos con logros en las nuestras, {len(pedir)} que bajar", file=sys.stderr)
    cache = {}
    for k, (gid, (o, g)) in enumerate(sorted(pedir.items())):
        ext = ra("API_GetGameExtended.php", i=gid)
        time.sleep(0.4)
        if not ext:
            continue
        achs = sorted((ext.get("Achievements") or {}).values(), key=lambda a: (a.get("DisplayOrder") or 0, a.get("ID") or 0))
        logros = [
            {"id": a.get("ID"), "nombre": a.get("Title", ""), "descripcion": a.get("Description", ""), "puntos": a.get("Points") or 0, "icono": RA_BADGE.format(a["BadgeName"]) if a.get("BadgeName") else None, "tipo": a.get("type") or None, "extra": {"mem": a["MemAddr"]} if a.get("MemAddr") else None}
            for a in achs
        ]
        if logros:
            titulo = ext.get("Title") or g["Title"]
            guardar_juego(db, "retroachievements", gid, titulo, o, logros)
            cache[str(gid)] = {"titulo": titulo, "origen": o, "logros": logros}
        if k % 50 == 0:
            db.commit()
            print(f"  RA {k}/{len(pedir)}", file=sys.stderr)
    db.commit()
    # Guardamos lo bajado para los builds que no tengan la clave
    if cache:
        CACHE_RA.parent.mkdir(parents=True, exist_ok=True)
        previo = json.load(open(CACHE_RA, encoding="utf-8")) if CACHE_RA.exists() else {}
        previo.update(cache)
        json.dump(previo, open(CACHE_RA, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
        print(f"RetroAchievements: {len(cache)} juegos guardados en {CACHE_RA}", file=sys.stderr)


def cargar_cache_ra(db):
    """Sin clave: usa las listas de RetroAchievements que ya se bajaron en otro build."""
    if not CACHE_RA.exists():
        return 0
    cache = json.load(open(CACHE_RA, encoding="utf-8"))
    for gid, g in cache.items():
        guardar_juego(db, "retroachievements", gid, g["titulo"], g["origen"], g["logros"])
    db.commit()
    return len(cache)


# ───────────────────────── enlazar con nuestros catálogos ─────────────────────────


def enlazar(db, catalogos, salida_json):
    # Qué fuente sirve para cada origen
    fuentes_por_origen = {"xbox360": ["xbox360", "xboxone"], "xboxone": ["xboxone"]}
    for o in RA_CONSOLAS:
        fuentes_por_origen.setdefault(o, []).append("retroachievements")
    idx, originales = {}, {}
    for fid, fuente, nombre, consola in db.execute("SELECT id, fuente, nombre, consola FROM juegos"):
        idx.setdefault((fuente, consola), {})[norm(nombre)] = fid
        originales.setdefault((fuente, consola), {})[norm(nombre)] = nombre
    db.execute("DELETE FROM vinculos")
    resumen = {}
    for cat, juegos in catalogos.items():
        out = Path(salida_json) / cat
        out.mkdir(parents=True, exist_ok=True)
        for f in out.glob("*.json"):
            f.unlink()
        resumen[cat] = 0
        for j in juegos:
            o = j.get("origen")
            sets = []
            for fuente in fuentes_por_origen.get(o, []):
                clave = (fuente, o if fuente == "retroachievements" else fuente)
                cand = idx.get(clave)
                if not cand or (fuente == "xboxone" and sets):
                    continue  # Xbox One solo si no hay lista de 360
                nombres = [j["nombre"], *j.get("proyectos", [])]
                fid, conf = None, 0
                for n in nombres:
                    fid, conf = mejor(n, cand, umbral=0.99 if fuente == "xboxone" else 0.92, nombres=originales[clave])
                    if fid:
                        break
                if not fid:
                    continue
                db.execute("INSERT INTO vinculos VALUES (?,?,?,?,?)", (cat, j["id"], fid, "nombre", conf))
                nombre, total, puntos = db.execute("SELECT nombre, total, puntos FROM juegos WHERE id = ?", (fid,)).fetchone()
                logros = [
                    {k: v for k, v in zip(("id", "nombre", "descripcion", "puntos", "icono", "tipo"), row) if v not in (None, "")}
                    for row in db.execute("SELECT fuente_id, nombre, descripcion, puntos, icono, tipo FROM logros WHERE juego = ? ORDER BY orden", (fid,))
                ]
                sets.append({"fuente": fuente, "nombre": nombre, "total": total, "puntos": puntos, "confianza": conf, "logros": logros})
            if sets:
                json.dump({"juego": j["id"], "sets": sets}, open(out / f"{j['id']}.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
                j["logros"] = [{"fuente": s["fuente"], "total": s["total"], "puntos": s["puntos"]} for s in sets]
                resumen[cat] += 1
            else:
                j.pop("logros", None)
    db.commit()
    return resumen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--xbox")
    ap.add_argument("--ra-todo", action="store_true")
    ap.add_argument("--out", default="build/logros")
    ap.add_argument("--catalogos", nargs="+", default=["data/juegos.json", "data/juegos-mac.json"])
    a = ap.parse_args()

    Path(a.out).mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(Path(a.out) / "logros.db")
    esquema(db)
    cats = {}
    for p in a.catalogos:
        cats["mac" if "mac" in os.path.basename(p) else "android"] = (p, json.load(open(p, encoding="utf-8")))
    catalogos = {k: v[1]["juegos"] for k, v in cats.items()}

    if a.xbox:
        cargar_xbox(db, a.xbox)
    if RA_KEY:
        cargar_ra(db, catalogos, todo=a.ra_todo)
    else:
        print(f"Sin RA_API_KEY: uso la caché de RetroAchievements ({cargar_cache_ra(db)} juegos)", file=sys.stderr)

    resumen = enlazar(db, catalogos, "data/logros")
    for k, (p, data) in cats.items():
        data.setdefault("_meta", {})["logros_generado"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        json.dump(data, open(p, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    juegos, logros = db.execute("SELECT COUNT(*) FROM juegos").fetchone()[0], db.execute("SELECT COUNT(*) FROM logros").fetchone()[0]
    por_fuente = dict(db.execute("SELECT fuente, COUNT(*) FROM juegos GROUP BY fuente").fetchall())
    db.execute("VACUUM")
    db.close()
    print(json.dumps({"juegos": juegos, "logros": logros, "por_fuente": por_fuente, "enlazados": resumen}, ensure_ascii=False))


if __name__ == "__main__":
    main()
