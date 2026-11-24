#!/usr/bin/env python3
"""Imágenes de SteamGridDB para el catálogo de Hangar.

Para cada juego busca en SteamGridDB las portadas (600x900), fondos (heroes) y logos más
votados y los guarda como alternativas en `arte_alt`, para elegirlas desde la app. Si el
juego no tenía portada, fondo o logo, pone el mejor directamente en `arte`.

Las imágenes elegidas a mano (arte_estado == "manual" o propuestas aprobadas por la comunidad)
no se tocan: solo se añaden alternativas.

Necesita la variable SGDB_API_KEY (steamgriddb.com → Preferences → API).
Guarda lo consultado en data/arte/cache-sgdb.json para no repetir consultas: cada ejecución
mira como mucho --max juegos nuevos (los más antiguos en caché se refrescan pasados 30 días).

Uso: SGDB_API_KEY=... python3 tools/arte/steamgriddb.py data/juegos.json data/juegos-mac.json
"""
import argparse
import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

API = "https://www.steamgriddb.com/api/v2"
RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(RAIZ, "data", "arte", "cache-sgdb.json")
POR_TIPO = 6
DIAS = 30


def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", s)
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


class SGDB:
    def __init__(self, clave):
        self.clave = clave
        self.peticiones = 0

    def get(self, ruta, **q):
        url = f"{API}{ruta}" + (f"?{urllib.parse.urlencode(q)}" if q else "")
        for intento in range(4):
            req = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.clave}", "User-Agent": "hangar-arte"})
            try:
                self.peticiones += 1
                with urllib.request.urlopen(req, timeout=25) as r:
                    data = json.load(r)
                time.sleep(0.25)  # sin prisas: es un servicio gratuito
                return data.get("data") or []
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    return []
                if e.code == 401:
                    sys.exit("SteamGridDB rechaza la clave (401): revisa el secreto SGDB_API_KEY.")
                if e.code == 429 or e.code >= 500:
                    time.sleep(5 * (intento + 1))
                    continue
                raise
            except (urllib.error.URLError, TimeoutError):
                time.sleep(3 * (intento + 1))
        return []

    def buscar(self, nombre):
        """El juego de SteamGridDB que mejor encaja con el nombre (o None)."""
        res = self.get(f"/search/autocomplete/{urllib.parse.quote(nombre, safe='')}")
        if not res:
            return None
        n = norm(nombre)
        exactos = [g for g in res if norm(g.get("name")) == n]
        if exactos:
            return exactos[0]
        # Si no hay uno exacto, solo vale el primero si se parece de verdad (mismos números incluidos).
        g = res[0]
        ng = norm(g.get("name"))
        nums = lambda s: re.findall(r"\d+", s)  # noqa: E731
        if nums(ng) != nums(n):
            return None
        palabras = set(n.split())
        comunes = palabras & set(ng.split())
        return g if palabras and len(comunes) / len(palabras) >= 0.75 else None

    def imagenes(self, gid):
        def lista(ruta, **q):
            items = [x for x in self.get(ruta, nsfw="false", humor="false", epilepsy="false", **q) if x.get("url")]
            items.sort(key=lambda x: (x.get("score") or 0, x.get("upvotes") or 0), reverse=True)
            return [{"url": x["url"], "thumb": x.get("thumb") or x["url"]} for x in items[:POR_TIPO]]

        return {
            "portada": lista(f"/grids/game/{gid}", dimensions="600x900", types="static"),
            "hero": lista(f"/heroes/game/{gid}", types="static"),
            "logo": lista(f"/logos/game/{gid}", types="static"),
        }


def cargar(path, defecto):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        return defecto


def guardar(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("catalogos", nargs="+")
    ap.add_argument("--max", type=int, default=150, help="juegos nuevos a consultar por ejecución")
    args = ap.parse_args()

    clave = os.environ.get("SGDB_API_KEY", "").strip()
    cache = cargar(CACHE, {})
    sgdb = SGDB(clave) if clave else None
    if not sgdb:
        print("Sin SGDB_API_KEY: solo se aplica lo que ya hay en la caché.")

    ahora = time.time()
    nuevos = 0
    for path in args.catalogos:
        cat = cargar(path, None)
        if not cat:
            continue
        cambios = 0
        # Primero los que no tienen imágenes, luego los de la portada (orden).
        juegos = sorted(cat["juegos"], key=lambda j: (bool((j.get("arte") or {}).get("portada")), j.get("orden", 9999)))
        for j in juegos:
            nombre = j.get("nombre") or ""
            clave_cache = norm(nombre)
            c = cache.get(clave_cache)
            caducada = c is None or ahora - c.get("t", 0) > DIAS * 86400
            if sgdb and caducada and nuevos < args.max:
                nuevos += 1
                try:
                    g = sgdb.buscar(nombre)
                    c = {"t": int(ahora), "id": g["id"] if g else None, "nombre": g.get("name") if g else None}
                    if g:
                        c.update(sgdb.imagenes(g["id"]))
                    cache[clave_cache] = c
                except Exception as e:  # noqa: BLE001
                    print(f"  {nombre}: {e}")
                if nuevos % 25 == 0:
                    guardar(CACHE, cache)
                    print(f"  … {nuevos} consultados ({sgdb.peticiones} peticiones)")
            if not c or not c.get("id"):
                continue

            alt = {k: c.get(k) or [] for k in ("portada", "hero", "logo")}
            alt = {k: v for k, v in alt.items() if v}
            if alt and j.get("arte_alt") != alt:
                j["arte_alt"] = alt
                cambios += 1
            # Lo que falta se rellena con la mejor opción, salvo que alguien lo haya elegido a mano.
            if j.get("arte_estado") == "manual":
                continue
            arte = j.get("arte") or {}
            puesto = False
            for k in ("portada", "hero", "logo"):
                if not arte.get(k) and alt.get(k):
                    arte[k] = alt[k][0]["url"]
                    arte[f"{k}_thumb"] = alt[k][0]["thumb"]
                    puesto = True
            if puesto:
                j["arte"] = arte
                j["arte_estado"] = "ok"
                cambios += 1
        if cambios:
            guardar(path, cat)
        con = sum(1 for j in cat["juegos"] if (j.get("arte") or {}).get("portada"))
        print(f"{os.path.basename(path)}: {cambios} juegos actualizados · {con}/{len(cat['juegos'])} con portada")

    guardar(CACHE, cache)
    sin = sum(1 for c in cache.values() if not c.get("id"))
    print(f"Caché: {len(cache)} juegos ({sin} sin encontrar en SteamGridDB) · {nuevos} consultados hoy")


if __name__ == "__main__":
    main()
