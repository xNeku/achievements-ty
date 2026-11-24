#!/usr/bin/env python3
"""Publicaciones de ports (issues de GitHub) -> catálogo de Hangar.

  revisar    Al abrir o editar la issue: comprueba el repositorio, su hangar.json, las descargas
             (APK / Mac) y las imágenes, y deja un comentario con lo que ha visto.
  aplicar    Cuando alguien del equipo pone la etiqueta «aprobado»: añade el port o las imágenes
             a data/juegos.json y/o data/juegos-mac.json.
  descubrir  Busca en GitHub repos con el tema «hangar-port» que aún no estén y prepara una issue
             para cada uno (build/descubiertos/N.titulo y N.md), ya revisada.

El texto de la issue lo escribe cualquiera: aquí solo se lee como datos (nunca se ejecuta ni
se mete en comandos), y lo que entra al catálogo se valida antes.

Uso: GITHUB_TOKEN=... python3 tools/propuestas.py revisar|aplicar|descubrir   (lee GITHUB_EVENT_PATH)
Salida: escribe en build/propuesta-comentario.md el comentario para la issue, y en
GITHUB_OUTPUT `cambiado=si|no` y `resumen=...`.
"""
import json
import os
import re
import sys
import unicodedata
import base64
import urllib.error
import urllib.request

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT_ANDROID = os.path.join(RAIZ, "data", "juegos.json")
CAT_MAC = os.path.join(RAIZ, "data", "juegos-mac.json")
TOKEN = os.environ.get("GITHUB_TOKEN", "")
TIPOS = {"decomp": "decomp", "recomp": "recomp", "source port": "source-port", "other": "port", "otro": "port"}
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from revisar_catalogo import manifiesto  # noqa: E402
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
        fh.write(texto.rstrip() + "\n\n---\n_Hangar bot._\n")


def buscar_juego(cat, nombre):
    n = norm(nombre)
    for j in cat["juegos"]:
        if norm(j.get("nombre")) == n or j.get("id") == slug(nombre):
            return j
    return None


# ───────────────────────── ports ─────────────────────────

def leer_manifiesto(repo):
    """El hangar.json del repositorio (validado), o {}."""
    try:
        c = http_json(f"https://api.github.com/repos/{repo}/contents/hangar.json")
        return manifiesto({"manifiesto": {"text": base64.b64decode(c.get("content", "")).decode("utf-8", "replace")}})
    except Exception:  # noqa: BLE001
        return {}


def analizar_port(f, quien=""):
    """Lee y comprueba la publicación. Devuelve (datos, avisos, errores)."""
    errores, avisos = [], []
    nombre = campo(f, "game", "nombre del juego").strip()[:120]
    url = campo(f, "github repository", "repositorio").strip()
    m = re.search(r"github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+?)(?:\.git)?(?:[/#?].*)?$", url)
    plat = campo(f, "platform", "plataforma").lower()
    tipo = TIPOS.get(campo(f, "project type", "tipo").lower(), "port")
    datos = {
        "nombre": nombre,
        "android": "android" in plat,
        "mac": "mac" in plat,
        "tipo": tipo,
        "requisitos": [l.strip("-* ").strip()[:200] for l in campo(f, "what players need", "que hace falta").splitlines() if l.strip()][:6],
        "archivo_mac": campo(f, "mac download", "archivo de la descarga").strip()[:120],
        "portada": campo(f, "cover", "portada").strip(),
        "hero": campo(f, "background", "imagen grande").strip(),
        "dice_autor": campo(f, "are you the developer").lower().startswith("yes"),
        "autor": False,
        "manifiesto": {},
    }
    if not nombre:
        errores.append("Missing the game name. · Falta el nombre del juego.")
    if not m:
        errores.append("The repository must be a GitHub link (https://github.com/user/project). · El repositorio tiene que ser un enlace de GitHub.")
        return datos, avisos, errores
    if not (datos["android"] or datos["mac"]):
        errores.append("Pick a platform. · Elige la plataforma.")

    try:
        info = http_json(f"https://api.github.com/repos/{m.group(1)}/{m.group(2)}")
    except urllib.error.HTTPError as e:
        errores.append(f"Can't find that repository on GitHub (HTTP {e.code}). · No encuentro el repositorio.")
        return datos, avisos, errores
    datos["repo"] = info["full_name"]
    datos["url"] = info["html_url"]
    datos["archivado"] = bool(info.get("archived"))
    datos["descripcion"] = (info.get("description") or "")[:300]
    if datos["archivado"]:
        avisos.append("The repository is archived. · El repositorio está archivado: ya no se actualiza.")

    # ¿Lo publica su autor? Su dueño en GitHub, o un hangar.json (solo puede subirlo quien tiene acceso al repo).
    man = leer_manifiesto(datos["repo"])
    datos["manifiesto"] = man
    es_dueno = quien and quien.lower() == datos["repo"].split("/")[0].lower()
    datos["autor"] = bool(man) or bool(es_dueno)
    if man:
        avisos.append("hangar.json found: the listing will follow it. · Tiene hangar.json: Hangar seguirá lo que diga.")
        datos["descripcion"] = man.get("descripcion") or datos["descripcion"]
        datos["requisitos"] = man.get("requisitos") or datos["requisitos"]
        if man.get("mac"):
            datos["archivo_mac"] = man["mac"]["asset"]
        for k in ("portada", "hero"):
            datos[k] = (man.get("arte") or {}).get(k) or datos[k]
    elif datos["dice_autor"] and not es_dueno:
        avisos.append(
            "To get the *author* badge, add a `hangar.json` to the repo (see PUBLISH.md). "
            "· Para el sello de *autor*, añade un `hangar.json` al repo."
        )

    try:
        releases = [r for r in http_json(f"https://api.github.com/repos/{datos['repo']}/releases?per_page=10") if not r.get("draft")]
    except urllib.error.HTTPError:
        releases = []
    nombres = [a["name"] for r in releases for a in r.get("assets", [])]
    datos["apks"] = [n for n in nombres if n.lower().endswith(".apk")]
    if not releases:
        avisos.append("No releases yet: Hangar can't install it until there is one. · No tiene releases: no se podrá instalar hasta que las tenga.")
    if datos["android"] and releases and not datos["apks"]:
        avisos.append("The latest releases have no APK: on Android only the project link will show. · Sin APK: en Android solo saldrá el enlace.")

    if datos["mac"]:
        if datos["archivo_mac"]:
            pat = re.compile("^" + ".*".join(map(re.escape, datos["archivo_mac"].split("*"))) + "$", re.I)
            if releases and not any(pat.match(n) for n in nombres):
                avisos.append(f"No file in the latest releases matches `{datos['archivo_mac']}`. · Ningún archivo se llama así.")
        else:
            candidatos = [n for n in nombres if MAC_PISTAS.search(n) and MAC_EXT.search(n)]
            if candidatos:
                # Se generaliza el número de versión para que siga valiendo en las siguientes.
                datos["archivo_mac"] = re.sub(r"\d+(?:\.\d+)+", "*", candidatos[0])
                avisos.append(f"For Mac I'll use `{datos['archivo_mac']}`. · Para Mac usaré ese archivo.")
            elif releases:
                avisos.append("No Mac download found in the latest releases: tell us the file name. · No encuentro descarga para Mac.")

    for k in ("portada", "hero"):
        if datos[k]:
            ok, motivo = es_imagen(datos[k])
            if not ok:
                avisos.append(f"The {'cover' if k == 'portada' else 'background'} image is not usable ({motivo}). · Esa imagen no vale.")
                datos[k] = ""

    for cat, quiere in ((CAT_ANDROID, datos["android"]), (CAT_MAC, datos["mac"])):
        if not quiere:
            continue
        for j in cargar(cat)["juegos"]:
            if any(r.get("repo", "").lower() == datos["repo"].lower() for r in j.get("repos", [])):
                errores.append(f"Already in the {'Mac' if cat == CAT_MAC else 'Android'} catalog ({j['nombre']}). · Ya está en el catálogo.")
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
        if datos["autor"]:
            repo["autor"] = True
            repo["autor_verificado"] = True
        if datos["requisitos"]:
            repo["requisitos"] = datos["requisitos"]
        if cat_path == CAT_MAC:
            if not datos["archivo_mac"]:
                continue
            repo["mac"] = {"asset": datos["archivo_mac"], **{k: v for k, v in (datos["manifiesto"].get("mac") or {}).items() if k != "asset"}}
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
    nombre = campo(f, "game", "juego").strip()
    datos = {"nombre": nombre, "img": {}}
    en = [p for p in (CAT_ANDROID, CAT_MAC) if buscar_juego(cargar(p), nombre)]
    datos["catalogos"] = en
    if not en:
        errores.append(f"Can't find «{nombre}» in Hangar: use the name shown in the app. · No encuentro ese juego.")
    for k, etiquetas in (("portada", ("cover", "portada")), ("hero", ("background", "imagen grande")), ("logo", ("logo",))):
        url = campo(f, *etiquetas).strip()
        if not url:
            continue
        ok, motivo = es_imagen(url)
        if ok:
            datos["img"][k] = url
        else:
            avisos.append(f"{k.capitalize()}: {motivo}.")
    if not datos["img"]:
        errores.append("No valid image. · No hay ninguna imagen válida.")
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


# ───────────────────────── descubrir ─────────────────────────

def descubrir(maximo=10):
    """Repos con el tema «hangar-port» que todavía no están en Hangar ni tienen issue."""
    conocidos = set()
    for p in (CAT_ANDROID, CAT_MAC):
        for j in cargar(p)["juegos"]:
            conocidos |= {r.get("repo", "").lower() for r in j.get("repos", [])}
    # Los que ya tienen issue (abierta o cerrada) no se repiten.
    pag = 1
    while pag <= 10:
        issues = http_json(f"https://api.github.com/repos/{os.environ.get('GITHUB_REPOSITORY', '')}/issues?labels=publicar-port&state=all&per_page=100&page={pag}")
        for it in issues:
            for m in re.finditer(r"github\.com/([\w-]+/[\w.-]+)", it.get("body") or ""):
                conocidos.add(m.group(1).lower().removesuffix(".git"))
        if len(issues) < 100:
            break
        pag += 1
    res = http_json("https://api.github.com/search/repositories?q=topic:hangar-port+fork:true&sort=updated&per_page=50")
    out_dir = os.path.join(RAIZ, "build", "descubiertos")
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for r in res.get("items", []):
        if n >= maximo or r["full_name"].lower() in conocidos:
            continue
        rels = []
        try:
            rels = http_json(f"https://api.github.com/repos/{r['full_name']}/releases?per_page=5")
        except Exception:  # noqa: BLE001
            pass
        nombres = [a["name"] for x in rels for a in x.get("assets", [])]
        android = any(x.lower().endswith(".apk") for x in nombres)
        mac = any(MAC_PISTAS.search(x) and MAC_EXT.search(x) for x in nombres) or bool(leer_manifiesto(r["full_name"]).get("mac"))
        if not (android or mac):
            continue
        plat = "Android + Mac" if android and mac else ("Android" if android else "Mac")
        nombre = re.sub(r"[-_]+", " ", r["name"]).strip()
        cuerpo = (
            f"### Game · Juego\n\n{nombre}\n\n### GitHub repository · Repositorio\n\n{r['html_url']}\n\n"
            f"### Platform · Plataforma\n\n{plat}\n\n### Project type · Tipo\n\nOther · Otro\n\n"
            f"### Are you the developer? · ¿Es tu proyecto?\n\nNo, I'm a fan · No, soy fan\n\n"
            f"### Anything else · Algo más\n\nFound automatically: the repo has the `hangar-port` topic. "
            f"Check the game name before approving. · Encontrado solo por el tema `hangar-port`: revisa el nombre antes de aprobar.\n"
        )
        f = leer_formulario(cuerpo)
        datos, avisos, errores = analizar_port(f, r["owner"]["login"])
        if errores:
            continue
        cuerpo += "\n---\n" + informe(datos, avisos, errores, False)
        with open(os.path.join(out_dir, f"{n}.titulo"), "w", encoding="utf-8") as fh:
            fh.write(f"[Port] {nombre}")
        with open(os.path.join(out_dir, f"{n}.md"), "w", encoding="utf-8") as fh:
            fh.write(cuerpo)
        n += 1
    print(f"{n} ports nuevos con el tema hangar-port")


# ───────────────────────── principal ─────────────────────────

def informe(datos, avisos, errores, imagenes):
    lista = lambda xs: "\n".join(f"- {x}" for x in xs)  # noqa: E731
    if errores:
        texto = "### Something needs fixing · Hay que corregir algo\n" + lista(errores)
    elif imagenes:
        texto = f"### Looks good · Pinta bien\nValid images for **{datos['nombre']}**: {', '.join(datos['img'])}."
    else:
        plats = " + ".join(p for p, q in (("Android", datos["android"]), ("Mac", datos["mac"])) if q)
        sello = " · ✔ by its author · del autor" if datos.get("autor") else ""
        texto = f"### Looks good · Pinta bien\n**{datos['nombre']}** · [{datos['repo']}]({datos['url']}) · {plats}{sello}"
        if datos.get("apks"):
            texto += f"\n\nAPK: {', '.join(sorted(set(datos['apks']))[:4])}"
    if avisos:
        texto += "\n\n**Notes · Avisos**\n" + lista(avisos)
    if not errores:
        texto += "\n\nOnce the team adds the `aprobado` label, it goes live in Hangar. · Cuando el equipo ponga la etiqueta `aprobado`, saldrá en Hangar."
    return texto


def main():
    modo = sys.argv[1] if len(sys.argv) > 1 else "revisar"
    if modo == "descubrir":
        return descubrir()
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as fh:
        issue = json.load(fh)["issue"]
    etiquetas = {l["name"] for l in issue.get("labels", [])}
    f = leer_formulario(issue.get("body"))
    imagenes = "imagenes" in etiquetas
    quien = (issue.get("user") or {}).get("login", "")

    datos, avisos, errores = analizar_imagenes(f) if imagenes else analizar_port(f, quien)
    lista = lambda xs: "\n".join(f"- {x}" for x in xs)  # noqa: E731

    if modo == "revisar":
        comentar(informe(datos, avisos, errores, imagenes))
        salida(cambiado="no", valido="no" if errores else "si")
        return

    # aplicar
    if errores:
        comentar("### Couldn't add it · No se ha podido añadir\n" + lista(errores) + "\n\nFix the issue and add the `aprobado` label again. · Corrige la issue y vuelve a poner la etiqueta.")
        salida(cambiado="no", valido="no")
        return
    hechos = aplicar_imagenes(datos) if imagenes else aplicar_port(datos, issue["number"])
    if not hechos:
        comentar("### Couldn't add it · No se ha podido añadir\nNo platform with a valid download (Mac needs the file name). · Ninguna plataforma tiene descarga válida.")
        salida(cambiado="no", valido="no")
        return
    que = "Images for " if imagenes else ""
    comentar(
        f"### Live in Hangar · Ya está en Hangar\n{que}**{datos['nombre']}** is now in the {' + '.join(hechos)} catalog. "
        "It shows up in the app in a few minutes, no update needed. Thanks! · Sale en la app en unos minutos, sin actualizarla. ¡Gracias!"
    )
    resumen = re.sub(r"[^\w .:'()#-]", "", f"{'Imágenes' if imagenes else 'Port'}: {datos['nombre']} (#{issue['number']})")[:100]
    salida(cambiado="si", valido="si", resumen=resumen)


if __name__ == "__main__":
    main()
