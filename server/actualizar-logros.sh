#!/usr/bin/env bash
# Baja de la última Release del repo la base de datos de logros y los catálogos, y los deja en /opt/hangar/logros
# (Caddy los sirve en https://<servidor>/logros/).
set -euo pipefail
DEST=/opt/hangar/logros
BASE=https://github.com/xNeku/achievements-ty/releases/latest/download
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for f in logros.db juegos.json juegos-mac.json; do
  curl -fsSL --retry 3 -o "$TMP/$f" "$BASE/$f"
done
install -m 644 "$TMP"/* "$DEST"/
chmod 755 "$DEST"
command -v restorecon >/dev/null && restorecon -R "$DEST" || true
echo "Logros actualizados: $(du -sh "$DEST" | cut -f1)"
