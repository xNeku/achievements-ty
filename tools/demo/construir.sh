#!/usr/bin/env bash
# Construye la vista previa de Hangar (la app web de verdad, con todo dentro) para el artefacto.
#   bash tools/demo/construir.sh <carpeta-salida>
# Luego se publica la carpeta: index.html es la página y lo demás va como archivos.
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Copia de la app y catálogo de demo (imágenes en local)"
(cd "$RAIZ/app" && tar --exclude=./build --exclude=./.dart_tool --exclude=./android --exclude=./macos --exclude=./ios -cf - .) | tar -xf - -C "$TMP"
python3 "$RAIZ/tools/demo/preparar.py" "$TMP"

echo "==> Compilando la versión web"
(cd "$TMP" && flutter build web --release --no-web-resources-cdn >/dev/null)
rm -rf "$OUT" && mkdir -p "$OUT/capturas"
cp -r "$TMP/build/web" "$OUT/app"
# Solo se usa CanvasKit: fuera los otros motores y los símbolos de depuración.
(cd "$OUT/app" && rm -rf canvaskit/skwasm* canvaskit/wimp* canvaskit/webparagraph canvaskit/*.symbols canvaskit/chromium/*.symbols .last_build_id)
cp "$RAIZ/tools/demo/vista.html" "$OUT/index.html"

echo "==> Capturas (plan B)"
(cd "$OUT" && python3 -m http.server 8799 >/dev/null 2>&1 & echo $! > "$TMP/srv")
sleep 1
CAPS="$(node "$RAIZ/tools/demo/capturas.js" "http://localhost:8799/app/index.html" "$OUT/capturas")"
kill "$(cat "$TMP/srv")" || true

python3 - "$OUT" "$CAPS" "$RAIZ" <<'PY'
import json, sys, subprocess, datetime
out, caps, raiz = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3]
n = lambda f: len(json.load(open(f"{raiz}/data/{f}"))["juegos"])
commit = subprocess.run(["git", "-C", raiz, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
json.dump({"fecha": datetime.date.today().strftime("%d/%m/%Y"), "android": n("juegos.json"), "mac": n("juegos-mac.json"),
           "commit": commit, "capturas": caps}, open(f"{out}/demo.json", "w"))
PY
echo "==> Listo: $(find "$OUT" -type f | wc -l) archivos, $(du -sh "$OUT" | cut -f1)"
