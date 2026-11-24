#!/usr/bin/env python3
"""Prepara la demo web de Hangar para el artefacto de vista previa.

Una página publicada no puede pedir nada a internet, así que la demo lleva dentro lo que enseña:
el catálogo con sus imágenes en local (las portadas de los primeros juegos y el arte grande de los
de la portada), los logros de esos juegos y las fuentes. El resto de juegos salen con su portada
generada, como en la app sin conexión.

Uso: python3 tools/demo/preparar.py <copia-de-app>   (modifica esa copia; luego `flutter build web`)
"""
import io
import json
import os
import re
import sys
import urllib.request

from PIL import Image

PORTADA = ['dark souls remastered', 'nier', 'majora', 'god of war iii', 'persona 5 royal', 'celeste', 'super mario galaxy', 'doom']
HEROES = 36       # juegos de la portada con arte grande y logo
PORTADAS = 120    # juegos con portada en la biblioteca


def bajar(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 hangar-demo'})
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.read()


def guardar(url, dest, ancho, formato):
    if os.path.exists(dest):
        return True
    try:
        im = Image.open(io.BytesIO(bajar(url)))
        if formato == 'JPEG':
            im = im.convert('RGB')
        elif im.mode not in ('RGBA', 'LA'):
            im = im.convert('RGBA')
        if im.width > ancho:
            im = im.resize((ancho, round(im.height * ancho / im.width)), Image.LANCZOS)
        im.save(dest, formato, **({'quality': 76, 'optimize': True, 'progressive': True} if formato == 'JPEG' else {'optimize': True}))
        return True
    except Exception as e:  # noqa: BLE001
        print('  sin imagen', url[:80], e)
        return False


def listo(j, mac):
    return any((r.get('mac') or {}).get('asset') if mac else r.get('android') for r in j.get('repos', []))


def rank(j, mac):
    """Mismo orden que el selector de la portada de la app (main.dart)."""
    arte = j.get('arte') or {}
    hero = bool(arte.get('hero') or arte.get('hero_thumb'))
    orden = j.get('orden', 9999)
    if orden < 9999:
        r0 = orden
    else:
        n = j['nombre'].lower()
        i = next((k for k, p in enumerate(PORTADA) if n.startswith(p)), -1)
        r0 = 100 + orden + (0 if hero else 20000) if i < 0 else i
    return (0 if listo(j, mac) else 100000) + r0, 0 if arte.get('logo') else 1, j['nombre'].lower()


def preparar(app, archivo, mac):
    path = os.path.join(app, 'assets', archivo)
    cat = json.load(open(path, encoding='utf-8'))
    juegos = cat['juegos']
    plat = 'mac' if mac else 'android'
    carpeta = os.path.join(app, 'web', 'demo', plat)
    os.makedirs(carpeta, exist_ok=True)

    portada = sorted([j for j in juegos if (j.get('arte') or {}).get('hero') or listo(j, mac)], key=lambda j: rank(j, mac))
    con_hero = [j for j in portada if (j.get('arte') or {}).get('hero')][:HEROES]
    ids_hero = {j['id'] for j in con_hero}
    # Portadas: las de la portada primero y luego las de los juegos listos para instalar.
    con_cover = [j for j in portada if (j.get('arte') or {}).get('portada')]
    elegidos = [j for j in con_cover if j['id'] in ids_hero] + [j for j in con_cover if j['id'] not in ids_hero]
    ids_cover = {j['id'] for j in elegidos[:PORTADAS]}

    for j in juegos:
        arte = j.get('arte') or {}
        nuevo = {}
        if j['id'] in ids_cover and guardar(arte.get('portada_thumb') or arte['portada'], f"{carpeta}/{j['id']}-p.jpg", 300, 'JPEG'):
            nuevo['portada'] = nuevo['portada_thumb'] = f"demo/{plat}/{j['id']}-p.jpg"
        if j['id'] in ids_hero:
            if guardar(arte.get('hero'), f"{carpeta}/{j['id']}-h.jpg", 1400, 'JPEG'):
                nuevo['hero'] = nuevo['hero_thumb'] = f"demo/{plat}/{j['id']}-h.jpg"
            if arte.get('logo') and guardar(arte['logo'], f"{carpeta}/{j['id']}-l.png", 560, 'PNG'):
                nuevo['logo'] = nuevo['logo_thumb'] = f"demo/{plat}/{j['id']}-l.png"
        j['arte'] = nuevo or None
        j.pop('arte_alt', None)

    # Solo los logros de los juegos de la portada, para no llenar la demo de archivos.
    dl = os.path.join(app, 'assets', 'logros', plat)
    if os.path.isdir(dl):
        for f in os.listdir(dl):
            if f[:-5] not in ids_hero:
                os.remove(os.path.join(dl, f))
    cat['_meta']['demo'] = True
    json.dump(cat, open(path, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    print(f'{archivo}: {len(ids_hero)} con arte grande, {len(ids_cover)} portadas')


if __name__ == '__main__':
    app = sys.argv[1]
    preparar(app, 'juegos.json', False)
    preparar(app, 'juegos-mac.json', True)
    # Sin <base href>: la demo se sirve dentro de una carpeta cuyo nombre no se conoce.
    idx = os.path.join(app, 'web', 'index.html')
    s = open(idx, encoding='utf-8').read()
    s = re.sub(r'\s*<base href="[^"]*">', '', s)
    # Avisa a la página que la contiene cuando la app ya se ha dibujado.
    s = s.replace('</body>', '''<script>
new MutationObserver((_, o) => { if (document.querySelector('flutter-view')) { o.disconnect(); try { parent.postMessage('hangar-listo', '*'); } catch (e) {} } })
  .observe(document.body, { childList: true, subtree: true });
</script>
</body>''')
    open(idx, 'w', encoding='utf-8').write(s)
