#!/usr/bin/env python3
"""Propuestas de la comunidad (issues de GitHub) -> catálogo de Hangar.

  revisar  Se ejecuta al abrir o editar la propuesta: comprueba el repositorio, busca las
           descargas (APK / Mac) y las imágenes, y deja un comentario con lo que ha visto.
  aplicar  Se ejecuta cuando alguien del equipo pone la etiqueta «aprobado»: añade el port
           o las imágenes a data/juegos.json y/o data/juegos-mac.json.

El texto de la issue lo escribe cualquiera: aquí solo se lee como datos (nunca se ejecuta ni
se mete en comandos), y lo que entra al catálogo se valida antes.

Uso: GITHUB_TOKEN=... python3 tools/propuestas.py revisar|aplicar   (lee GITHUB_EVENT_PATH)
Salida: escribe en build/propuesta-comentario.md el comentario para la issue, y en
GITHUB_OUTPUT `cambiado=si|no` y `resumen=...`.
"""
import json
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.request

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT_ANDROID = os.path.join(RAIZ, "data", "juegos.json")
CAT_MAC = os.path.join(RAIZ, "data", "juegos-mac.json")
TOKEN = os.environ.get("GITHUB_TOKEN", "")
TIPOS = {"decomp": "decomp", "recomp": "recomp", "source port": "source-port", "otro": "port"}
MAC_PISTAS = re.compile(r"mac|macos|osx|darwin|apple|universal", re.I)
MAC_EXT = re.compile(r"\.(zip|dmg|tar\.gz|tgz|tar\.xz|7z)$", re.I)


# ───────────────────────── utilidades ─────────────────────────

def http_json(url):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "hangar-propuestas"})
    if TOKEN and url.startswith("https://api.github.com/"):
        req.add_header("Authorization", f"Bearer {TOKEN}")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def es_imagen(url):
    """¿El enlace es una imagen accesible? Devuelve (ok, motivo)."""
    if not re.match(r"^https://[^\s<>\"']+$", url or ""):
        return False, "tiene que ser un enlace https directo"
    try:
        req = urllib.request.Request(url, method="GET", headers={"User-Agent": "hangar-propuestas", "Range": "bytes=0-1023"})
        with urllib.request.urlopen(req, timeout=20) as r:
            tipo = r.headers.get("Content-Type", "")
            if not tipo.startswith("image/"):
                return False, f"no es una imagen ({tipo or 'tipo desconocido'})"
    except Exception as e:  # noqa: BLE001
        return False, f"no se puede abrir ({e.__class__.__name__})"
    return True, "ok"


def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def slug(s):
    return norm(s).replace(" ", "-")[:80] or "juego"


def leer_formulario(cuerpo):
    """Las issues de formulario llegan como «### Etiqueta\\n\\nvalor». Devuelve {etiqueta normalizada: valor}."""
    campos = {}
    for bloque in re.split(r"^### ", cuerpo or "", flags=re.M)[1:]:
        titulo, _, valor = bloque.partition("\n")
        valor = valor.strip()
        if valor == "_No response_":
            valor = ""
        campos[norm(titulo)] = valor
    return campos


def campo(f, *claves):
    for k in claves:
        for titulo, v in f.items():
            if titulo.startswith(k):
                return v
    return ""


def cargar(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def guardar(path, data):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))


def salida(**kv):
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            for k, v in kv.items():
                fh.write(f"{k}={v}\n")


def comentar(texto):
    os.makedirs(os.path.join(RAIZ, "build"), exist_ok=True)
    with open(os.path.join(RAIZ, "build", "propuesta-comentario.md"), "w", encoding="utf-8") as fh:
        fh.write(texto.rstrip() + "\n\n---\n_Mensaje automático de Hangar._\n")


def buscar_juego(cat, nombre):
    n = norm(nombre)
    for j in cat["juegos"]:
        if norm(j.get("nombre")) == n or j.get("id") == slug(nombre):
            return j
    return None


# ───────────────────────── ports ─────────────────────────

def analizar_port(f):
    """Lee y comprueba la propuesta. Devuelve (datos, avisos, errores)."""
    errores, avisos = [], []
    nombre = campo(f, "nombre del juego").strip()[:120]
    url = campo(f, "repositorio").strip()
    m = re.search(r"github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+?)(?:\.git)?(?:[/#?].*)?$", url)
    plat = campo(f, "plataforma").lower()
    tipo = TIPOS.get(campo(f, "tipo").lower(), "port")
    datos = {
        "nombre": nombre,
        "android": "android" in plat,
        "mac": "mac" in plat,
        "tipo": tipo,
        "requisitos": [l.strip("-* ").strip()[:200] for l in campo(f, "que hace falta").splitlines() if l.strip()][:6],
        "archivo_mac": campo(f, "archivo de la descarga").strip()[:120],
        "portada": campo(f, "portada").strip(),
        "hero": campo(f, "imagen grande").strip(),
    }
    if not nombre:
        errores.append("Falta el nombre del juego.")
    if not m:
        errores.append("El repositorio tiene que ser un enlace de GitHub (https://github.com/usuario/proyecto).")
        return datos, avisos, errores
    if not (datos["android"] or datos["mac"]):
        errores.append("Elige la plataforma.")

    try:
        info = http_json(f"https://api.github.com/repos/{m.group(1)}/{m.group(2)}")
    except urllib.error.HTTPError as e:
        errores.append(f"No encuentro el repositorio en GitHub (HTTP {e.code}).")
        return datos, avisos, errores
    datos["repo"] = info["full_name"]
    datos["url"] = info["html_url"]
    datos["archivado"] = bool(info.get("archived"))
    datos["descripcion"] = (info.get("description") or "")[:300]
    if datos["archivado"]:
        avisos.append("El repositorio está archivado: ya no se actualiza.")

    try:
        releases = [r for r in http_json(f"https://api.github.com/repos/{datos['repo']}/releases?per_page=10") if not r.get("draft")]
    except urllib.error.HTTPError:
        releases = []
    nombres = [a["name"] for r in releases for a in r.get("assets", [])]
    datos["apks"] = [n for n in nombres if n.lower().endswith(".apk")]
    if not releases:
        avisos.append("No tiene ninguna versión publicada (releases): Hangar no podrá instalarlo hasta que la tenga.")
    if datos["android"] and releases and not datos["apks"]:
        avisos.append("Las últimas versiones no traen ningún APK: en Android solo saldrá el enlace al proyecto.")

    if datos["mac"]:
        if datos["archivo_mac"]:
            pat = re.compile("^" + ".*".join(map(re.escape, datos["archivo_mac"].split("*"))) + "$", re.I)
            if releases and not any(pat.match(n) for n in nombres):
                avisos.append(f"Ningún archivo de las últimas versiones se llama «{datos['archivo_mac']}».")
        else:
            candidatos = [n for n in nombres if MAC_PISTAS.search(n) and MAC_EXT.search(n)]
            if candidatos:
                # Se generaliza el número de versión para que siga valiendo en las siguientes.
                datos["archivo_mac"] = re.sub(r"\d+(?:\.\d+)+", "*", candidatos[0])
                avisos.append(f"Para Mac usaré el archivo «{datos['archivo_mac']}».")
            elif releases:
                avisos.append("No encuentro una descarga para Mac en las últimas versiones. Indica el nombre del archivo.")

    for k in ("portada", "hero"):
        if datos[k]:
            ok, motivo = es_imagen(datos[k])
            if not ok:
                avisos.append(f"La {'portada' if k == 'portada' else 'imagen de fondo'} {motivo}: no la usaré.")
                datos[k] = ""

    for cat, quiere in ((CAT_ANDROID, datos["android"]), (CAT_MAC, datos["mac"])):
        if not quiere:
            continue
        for j in cargar(cat)["juegos"]:
            if any(r.get("repo", "").lower() == datos["repo"].lower() for r in j.get("repos", [])):
                errores.append(f"Este repositorio ya está en el catálogo de {'Mac' if cat == CAT_MAC else 'Android'} ({j['nombre']}).")
    return datos, avisos, errores


def aplicar_port(datos, issue):
    hechos = []
    for cat_path, quiere in ((CAT_ANDROID, datos["android"]), (CAT_MAC, datos["mac"])):
        if not quiere:
            continue
        cat = cargar(cat_path)
        repo = {
            "repo": datos["repo"],
            "url": datos["url"],
            "tipo": datos["tipo"],
            "nombre_en_catalogo": datos["nombre"],
            "archivado": datos["archivado"],
            "propuesta": issue,
        }
        if datos["requisitos"]:
            repo["requisitos"] = datos["requisitos"]
        if cat_path == CAT_MAC:
            if not datos["archivo_mac"]:
                continue
            repo["mac"] = {"asset": datos["archivo_mac"]}
            if datos["requisitos"]:
                repo["mac"]["necesita"] = datos["requisitos"][0]
        j = buscar_juego(cat, datos["nombre"])
        if j is None:
            ids = {x["id"] for x in cat["juegos"]}
            nid, n = slug(datos["nombre"]), 2
            while nid in ids:
                nid, n = f"{slug(datos['nombre'])}-{n}", n + 1
            j = {
                "id": nid,
                "nombre": datos["nombre"],
                "proyectos": [],
                "plataforma": None,
                "tipos": [datos["tipo"]],
                "repos": [],
                "confianza_nombre": "comunidad",
                "notas": [],
                "arte_estado": "pendiente",
                "arte": None,
                "origen": None,
            }
            if datos["descripcion"]:
                j["descripcion"] = datos["descripcion"]
            cat["juegos"].append(j)
        elif datos["tipo"] not in j.setdefault("tipos", []):
            j["tipos"].append(datos["tipo"])
        j.setdefault("repos", []).append(repo)
        poner_arte(j, {"portada": datos["portada"], "hero": datos["hero"]})
        cat["juegos"].sort(key=lambda x: norm(x.get("nombre")))
        guardar(cat_path, cat)
        hechos.append("Mac" if cat_path == CAT_MAC else "Android")
    return hechos


# ───────────────────────── imágenes ─────────────────────────

def poner_arte(j, nuevas):
    nuevas = {k: v for k, v in nuevas.items() if v}
    if not nuevas:
        return
    arte = j.get("arte") or {}
    for k, v in nuevas.items():
        arte[k] = v
        arte[f"{k}_thumb"] = v
    j["arte"] = arte
    j["arte_estado"] = "ok" if arte.get("portada") or arte.get("hero") else j.get("arte_estado", "pendiente")


def analizar_imagenes(f):
    errores, avisos = [], []
    nombre = campo(f, "juego").strip()
    datos = {"nombre": nombre, "img": {}}
    en = [p for p in (CAT_ANDROID, CAT_MAC) if buscar_juego(cargar(p), nombre)]
    datos["catalogos"] = en
    if not en:
        errores.append(f"No encuentro «{nombre}» en Hangar. Escribe el nombre tal como sale en la app.")
    for k, etiqueta in (("portada", "portada"), ("hero", "imagen grande"), ("logo", "logo")):
        url = campo(f, etiqueta).strip()
        if not url:
            continue
        ok, motivo = es_imagen(url)
        if ok:
            datos["img"][k] = url
        else:
            avisos.append(f"{k.capitalize()}: {motivo}.")
    if not datos["img"]:
        errores.append("No hay ninguna imagen válida.")
    return datos, avisos, errores


def aplicar_imagenes(datos):
    hechos = []
    for p in datos["catalogos"]:
        cat = cargar(p)
        j = buscar_juego(cat, datos["nombre"])
        poner_arte(j, datos["img"])
        guardar(p, cat)
        hechos.append("Mac" if p == CAT_MAC else "Android")
    return hechos


# ───────────────────────── principal ─────────────────────────

def main():
    modo = sys.argv[1] if len(sys.argv) > 1 else "revisar"
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as fh:
        issue = json.load(fh)["issue"]
    etiquetas = {l["name"] for l in issue.get("labels", [])}
    f = leer_formulario(issue.get("body"))
    imagenes = "imagenes" in etiquetas

    datos, avisos, errores = analizar_imagenes(f) if imagenes else analizar_port(f)
    lista = lambda xs: "\n".join(f"- {x}" for x in xs)  # noqa: E731

    if modo == "revisar":
        if errores:
            texto = "### Hay que corregir algo\n" + lista(errores)
        elif imagenes:
            texto = f"### Pinta bien\nImágenes válidas para **{datos['nombre']}**: {', '.join(datos['img'])}."
        else:
            plats = " y ".join(p for p, q in (("Android", datos["android"]), ("Mac", datos["mac"])) if q)
            texto = f"### Pinta bien\n**{datos['nombre']}** · [{datos['repo']}]({datos['url']}) · {plats}"
            if datos.get("apks"):
                texto += f"\n\nAPK encontrados: {', '.join(sorted(set(datos['apks']))[:4])}"
        if avisos:
            texto += "\n\n**Avisos**\n" + lista(avisos)
        if not errores:
            texto += "\n\nCuando alguien del equipo le ponga la etiqueta `aprobado`, entrará en el catálogo."
        comentar(texto)
        salida(cambiado="no", valido="no" if errores else "si")
        return

    # aplicar
    if errores:
        comentar("### No se ha podido añadir\n" + lista(errores) + "\n\nCorrige la issue y vuelve a poner la etiqueta `aprobado`.")
        salida(cambiado="no", valido="no")
        return
    hechos = aplicar_imagenes(datos) if imagenes else aplicar_port(datos, issue["number"])
    if not hechos:
        comentar("### No se ha podido añadir\nNo hay ninguna plataforma con descarga válida (para Mac hace falta el nombre del archivo).")
        salida(cambiado="no", valido="no")
        return
    que = "Las imágenes de " if imagenes else ""
    comentar(
        f"### Añadido\n{que}**{datos['nombre']}** ya está en el catálogo de {' y '.join(hechos)}. "
        "Aparecerá en Hangar en unos minutos, sin actualizar la app. ¡Gracias!"
    )
    resumen = re.sub(r"[^\w .:'()#-]", "", f"{'Imágenes' if imagenes else 'Port'}: {datos['nombre']} (#{issue['number']})")[:100]
    salida(cambiado="si", valido="si", resumen=resumen)


if __name__ == "__main__":
    main()
