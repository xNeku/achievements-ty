#!/usr/bin/env python3
"""Revisa en GitHub cada port de los catálogos y anota lo que Hangar necesita para instalarlo.

Para cada repo consulta (por GraphQL, en lotes) sus últimas releases, si está archivado y su README:

- Android (data/juegos.json): el APK más reciente que se pueda instalar (prefiere arm64 o universal)
  -> repo["android"] = {tag, apk, url, size, pre}
- Mac (data/juegos-mac.json): la release más reciente cuyo archivo encaje con el patrón del catálogo
  -> actualiza repo["mac"] (tag, file, version, url) y quita el sha256 si el archivo ha cambiado.
- Ambos: repo["archivado"] y repo["requisitos"] (frases del README sobre la ROM o el disco que pide).

Uso: GITHUB_TOKEN=... python3 tools/revisar_catalogo.py data/juegos.json data/juegos-mac.json
"""

import json
import os
import re
import sys
import time
import urllib.request

API = "https://api.github.com/graphql"
TOKEN = os.environ.get("GITHUB_TOKEN", "")
LOTE = 20

QUERY_REPO = """
  r{i}: repository(owner: {owner}, name: {name}) {{
    isArchived
    releases(first: 8, orderBy: {{field: CREATED_AT, direction: DESC}}) {{
      nodes {{ tagName isPrerelease isDraft releaseAssets(first: 50) {{ nodes {{ name size downloadUrl }} }} }}
    }}
    readme: object(expression: "HEAD:README.md") {{ ... on Blob {{ text }} }}
  }}"""

PALABRAS = re.compile(
    r"\b(rom|roms|iso|isos|baserom|dump|dumped|\.z64|\.n64|\.v64|\.gba|\.nds|\.3ds|\.xex|\.xci|\.nsp|\.wbfs|\.rvz|\.cue|\.bin|\.chd|"
    r"own copy|legal copy|legally|your copy|game files|assets from|tu copia)\b",
    re.I,
)


def gql(query):
    body = json.dumps({"query": query}).encode()
    for intento in range(4):
        req = urllib.request.Request(API, data=body, headers={"Authorization": f"bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "hangar-catalog"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            print(f"  reintento {intento + 1}: {e}", file=sys.stderr)
            time.sleep(5 * (intento + 1))
    return {"data": {}}


def limpiar(linea):
    linea = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", linea)
    linea = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", linea)
    linea = re.sub(r"<[^>]+>", "", linea)
    linea = re.sub(r"[*_`#>|]", "", linea)
    return re.sub(r"\s+", " ", linea).strip(" -:•\t")


def requisitos(readme):
    if not readme:
        return []
    out = []
    for raw in readme.splitlines():
        t = limpiar(raw)
        if 25 <= len(t) <= 400 and PALABRAS.search(t) and not t.lower().startswith(("http", "copyright")):
            t = t if len(t) <= 220 else t[:217].rsplit(" ", 1)[0] + "…"
            if t not in out:
                out.append(t)
        if len(out) == 3:
            break
    return out


def puntos_apk(nombre):
    n = nombre.lower()
    return (3 if ("arm64" in n or "v8a" in n) else 0) + (2 if "universal" in n else 0) - (5 if "x86" in n else 0) - (2 if "debug" in n else 0) - (1 if "armeabi-v7a" in n and "arm64" not in n else 0)


def patron(glob):
    return re.compile("^" + ".*".join(re.escape(p) for p in glob.split("*")) + "$", re.I)


def revisar(path, mac):
    cat = json.load(open(path, encoding="utf-8"))
    repos = []
    for j in cat["juegos"]:
        for r in j["repos"]:
            if re.fullmatch(r"[\w.-]+/[\w.-]+", r.get("repo", "")):
                repos.append(r)
    unicos = sorted({r["repo"] for r in repos})
    info = {}
    for i in range(0, len(unicos), LOTE):
        trozo = unicos[i : i + LOTE]
        partes = [QUERY_REPO.format(i=k, owner=json.dumps(rp.split("/")[0]), name=json.dumps(rp.split("/")[1])) for k, rp in enumerate(trozo)]
        res = gql("query {" + "".join(partes) + "\n}")
        data = res.get("data") or {}
        for k, rp in enumerate(trozo):
            info[rp] = data.get(f"r{k}")
        print(f"{path}: {min(i + LOTE, len(unicos))}/{len(unicos)}", file=sys.stderr)

    listos = 0
    for r in repos:
        d = info.get(r["repo"])
        if not d:
            r.pop("android", None)
            continue
        r["archivado"] = bool(d.get("isArchived"))
        req = requisitos((d.get("readme") or {}).get("text"))
        if req:
            r["requisitos"] = req
        rels = [x for x in (d.get("releases") or {}).get("nodes") or [] if not x.get("isDraft")]
        if mac:
            m = r.get("mac") or {}
            if not m.get("asset"):
                continue
            pat = patron(m["asset"])
            for rel in rels:
                a = next((a for a in rel["releaseAssets"]["nodes"] if pat.match(a["name"])), None)
                if a:
                    if a["name"] != m.get("file"):
                        m.pop("sha256", None)
                    m.update(tag=rel["tagName"], file=a["name"], url=a["downloadUrl"], version=rel["tagName"].lstrip("vV"))
                    listos += 1
                    break
        else:
            r.pop("android", None)
            for rel in rels:
                apks = sorted((a for a in rel["releaseAssets"]["nodes"] if a["name"].lower().endswith(".apk")), key=lambda a: -puntos_apk(a["name"]))
                if apks:
                    a = apks[0]
                    r["android"] = {"tag": rel["tagName"], "apk": a["name"], "url": a["downloadUrl"], "size": a["size"], "pre": bool(rel.get("isPrerelease"))}
                    listos += 1
                    break
    cat.setdefault("_meta", {})["revisado"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    json.dump(cat, open(path, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print(f"{path}: {listos} ports listos para instalar de {len(repos)}")


if __name__ == "__main__":
    if not TOKEN:
        sys.exit("Falta GITHUB_TOKEN")
    for p in sys.argv[1:]:
        revisar(p, mac="mac" in os.path.basename(p))
