#!/usr/bin/env bash
# Instala o actualiza el servidor de Hangar en un VPS con AlmaLinux / Rocky / RHEL 8 o 9.
#
#   curl -fsSL https://raw.githubusercontent.com/xNeku/achievements-ty/main/server/instalar.sh | sudo RAMA=main bash
#
# Variables opcionales: RAMA (rama del repo, por defecto main), HOST (nombre del servidor; por defecto
# <ip-con-guiones>.sslip.io, que no necesita dominio), ADMIN_EMAIL y ADMIN_PASS (cuenta del panel).
# Se puede ejecutar las veces que haga falta: solo cambia lo que falte o lo que haya cambiado.
set -euo pipefail

RAMA="${RAMA:-main}"
REPO="xNeku/achievements-ty"
RAW="https://raw.githubusercontent.com/$REPO/$RAMA/server"
PB_VERSION="0.22.22"
DIR=/opt/hangar

[ "$(id -u)" = 0 ] || { echo "Ejecútalo como root (con sudo)."; exit 1; }

IP="$(curl -fsS --max-time 10 https://api.ipify.org || hostname -I | awk '{print $1}')"
HOST="${HOST:-$(echo "$IP" | tr . -).sslip.io}"
case "$(uname -m)" in x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; *) echo "Arquitectura no soportada: $(uname -m)"; exit 1 ;; esac

paso() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

paso "Paquetes del sistema"
dnf -y -q install curl unzip tar dnf-plugins-core policycoreutils-python-utils >/dev/null

paso "Memoria de intercambio (1 GB) para que 2 GB de RAM vayan holgados"
if ! swapon --show | grep -q .; then
  fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap -q /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "Swap activado."
else
  echo "Ya había swap."
fi

paso "Usuario y carpetas"
id hangar &>/dev/null || useradd --system --home-dir "$DIR" --shell /sbin/nologin hangar
mkdir -p "$DIR"/{pb_data,pb_migrations,pb_public,logros}

paso "PocketBase $PB_VERSION"
if ! "$DIR/pocketbase" --version 2>/dev/null | grep -q "$PB_VERSION"; then
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/pb.zip" "https://github.com/pocketbase/pocketbase/releases/download/v$PB_VERSION/pocketbase_${PB_VERSION}_linux_${ARCH}.zip"
  unzip -o -q "$TMP/pb.zip" pocketbase -d "$DIR"
  rm -rf "$TMP"
fi
"$DIR/pocketbase" --version

paso "Esquema de datos y servicios"
curl -fsSL -o "$DIR/pb_migrations/1732400000_hangar.js" "$RAW/pb_migrations/1732400000_hangar.js"
curl -fsSL -o "$DIR/actualizar-logros.sh" "$RAW/actualizar-logros.sh"
chmod +x "$DIR/actualizar-logros.sh"
for f in hangar.service hangar-logros.service hangar-logros.timer; do
  curl -fsSL -o "/etc/systemd/system/$f" "$RAW/$f"
done
chown -R hangar:hangar "$DIR"
chmod 755 "$DIR" "$DIR/logros"

paso "Cuenta de administración del panel"
NUEVA_CLAVE=""
if [ ! -f "$DIR/pb_data/data.db" ]; then
  ADMIN_EMAIL="${ADMIN_EMAIL:-admin@hangar.app}"
  ADMIN_PASS="${ADMIN_PASS:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)}"
  sudo -u hangar "$DIR/pocketbase" migrate up --dir="$DIR/pb_data" --migrationsDir="$DIR/pb_migrations" >/dev/null
  sudo -u hangar "$DIR/pocketbase" admin create "$ADMIN_EMAIL" "$ADMIN_PASS" --dir="$DIR/pb_data"
  NUEVA_CLAVE="$ADMIN_PASS"
else
  echo "Ya existe (no se toca)."
fi

paso "Caddy (HTTPS automático)"
if ! command -v caddy >/dev/null; then
  dnf -y -q copr enable @caddy/caddy >/dev/null
  dnf -y -q install caddy >/dev/null
fi
curl -fsSL "$RAW/Caddyfile.tmpl" | sed "s/{{HOST}}/$HOST/" > /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null

paso "SELinux y cortafuegos"
if command -v getenforce >/dev/null && [ "$(getenforce)" != "Disabled" ]; then
  setsebool -P httpd_can_network_connect 1 || true
  semanage fcontext -a -t httpd_sys_content_t "$DIR/logros(/.*)?" 2>/dev/null || semanage fcontext -m -t httpd_sys_content_t "$DIR/logros(/.*)?" || true
  restorecon -R "$DIR/logros" || true
fi
if systemctl is-active --quiet firewalld; then
  firewall-cmd -q --permanent --add-service=http --add-service=https
  firewall-cmd -q --reload
fi

paso "Arrancando"
systemctl daemon-reload
systemctl enable -q --now hangar.service caddy.service hangar-logros.timer
systemctl restart hangar.service caddy.service
systemctl start --no-block hangar-logros.service

sleep 3
paso "Listo"
echo "Servidor:          https://$HOST"
echo "Panel de admin:    https://$HOST/_/"
echo "Logros:            https://$HOST/logros/logros.db  (se actualiza cada noche)"
if [ -n "$NUEVA_CLAVE" ]; then
  echo
  echo "Cuenta del panel:  $ADMIN_EMAIL"
  echo "Contraseña:        $NUEVA_CLAVE"
  echo "Guárdala: no se vuelve a mostrar. Puedes cambiarla en el panel."
fi
echo
echo "Si la web no abre en un par de minutos, abre los puertos 80 y 443 en el panel de Raiola (cortafuegos externo)."
systemctl --no-pager --lines=0 status hangar.service caddy.service | grep -E 'Active:|●' || true
