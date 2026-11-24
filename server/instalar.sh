#!/usr/bin/env bash
# Instala o actualiza el servidor de Hangar en un VPS con AlmaLinux / Rocky / RHEL 8 o 9.
#
#   curl -fsSL https://raw.githubusercontent.com/xNeku/achievements-ty/main/server/instalar.sh | sudo RAMA=main bash
#
# Variables opcionales: RAMA (rama del repo, por defecto main), HOST (nombre del servidor; por defecto
# <ip-con-guiones>.sslip.io, que no necesita dominio), ADMIN_EMAIL y ADMIN_PASS (cuenta del panel).
# Se puede ejecutar las veces que haga falta: solo cambia lo que falte o lo que haya cambiado.
set -euo pipefail
trap 'echo; echo "ERROR en la línea $LINENO: $BASH_COMMAND"; echo "Mándale a Claude esta salida."' ERR

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
if swapon --show | grep -q .; then
  echo "Ya hay swap activo."
elif systemd-detect-virt -cq 2>/dev/null; then
  echo "El VPS es un contenedor ($(systemd-detect-virt -c)) y no permite swap: seguimos sin él (2 GB bastan)."
else
  [ -f /swapfile ] || fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  if swapon /swapfile 2>/dev/null; then
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap activado."
  else
    echo "Este VPS no permite swap: seguimos sin él (2 GB bastan)."
  fi
fi
# Si el swap no se pudo activar, no dejamos restos (ni el archivo ni la línea en /etc/fstab).
if ! swapon --show 2>/dev/null | grep -q '^/swapfile'; then
  sed -i '\|^/swapfile |d' /etc/fstab
  rm -f /swapfile
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

paso "Base de datos y cuenta de administración del panel"
pb() { (cd "$DIR" && runuser -u hangar -- "$DIR/pocketbase" "$@" --dir="$DIR/pb_data" --migrationsDir="$DIR/pb_migrations"); }
systemctl stop hangar.service 2>/dev/null || true
pb migrate up
NUEVA_CLAVE=""
if [ ! -f "$DIR/.admin-creado" ]; then
  ADMIN_EMAIL="${ADMIN_EMAIL:-admin@hangar.app}"
  ADMIN_PASS="${ADMIN_PASS:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)}"
  # Si quedó una cuenta de un intento anterior, se le pone la contraseña nueva.
  pb admin create "$ADMIN_EMAIL" "$ADMIN_PASS" 2>/dev/null || pb admin update "$ADMIN_EMAIL" "$ADMIN_PASS"
  touch "$DIR/.admin-creado"
  NUEVA_CLAVE="$ADMIN_PASS"
else
  echo "Ya estaba creada (no se toca). Para cambiarla: sudo runuser -u hangar -- $DIR/pocketbase admin update admin@hangar.app NUEVA --dir=$DIR/pb_data"
fi
chown -R hangar:hangar "$DIR"

paso "Caddy (HTTPS automático)"
if ! command -v caddy >/dev/null; then
  dnf -y -q copr enable @caddy/caddy >/dev/null
  dnf -y -q install caddy >/dev/null
fi
# Si otro programa (p. ej. SSH) ya usa el 443, HTTPS va por el 8443. El certificado se saca por el 80.
OCUPA_443="$(ss -ltnpH 2>/dev/null | awk '$4 ~ /:443$/' | grep -v caddy || true)"
if [ -z "${HTTPS_PORT:-}" ]; then
  if [ -n "$OCUPA_443" ]; then HTTPS_PORT=8443; else HTTPS_PORT=443; fi
fi
if [ "$HTTPS_PORT" = 443 ]; then
  SITE="$HOST"; GLOBAL=""; URL="https://$HOST"
else
  echo "El puerto 443 lo usa otro programa ($(echo "$OCUPA_443" | grep -o 'users:(("[^"]*' | head -1 | cut -d'"' -f2)): Hangar irá por el $HTTPS_PORT."
  SITE="$HOST:$HTTPS_PORT"; GLOBAL="{\n\thttps_port $HTTPS_PORT\n}"; URL="https://$HOST:$HTTPS_PORT"
fi
curl -fsSL "$RAW/Caddyfile.tmpl" | sed "s|{{SITE}}|$SITE|; s|{{GLOBAL}}|$GLOBAL|" > /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1
# En contenedores (OpenVZ/LXC) systemd no puede aislar a Caddy como hace por defecto: se lo quitamos.
if systemd-detect-virt -cq 2>/dev/null; then
  mkdir -p /etc/systemd/system/caddy.service.d
  cat > /etc/systemd/system/caddy.service.d/contenedor.conf <<'CONF'
[Service]
PrivateTmp=false
PrivateDevices=false
ProtectSystem=false
ProtectHome=false
ProtectKernelTunables=false
ProtectKernelModules=false
ProtectControlGroups=false
CONF
fi
# ¿Hay otro servidor web ocupando los puertos que necesita Caddy?
OCUPADOS="$(ss -ltnpH 2>/dev/null | awk -v p=":$HTTPS_PORT\$" '$4 ~ /:80$/ || $4 ~ p' | grep -v caddy || true)"
if [ -n "$OCUPADOS" ]; then
  echo "Aviso: algo más está usando el puerto 80 o el $HTTPS_PORT y Caddy no podrá arrancar:"
  echo "$OCUPADOS"
  echo "Si es Apache o nginx y no lo usas: systemctl disable --now httpd nginx"
fi

paso "SELinux y cortafuegos"
if command -v getenforce >/dev/null && [ "$(getenforce)" != "Disabled" ]; then
  setsebool -P httpd_can_network_connect 1 || true
  semanage fcontext -a -t httpd_sys_content_t "$DIR/logros(/.*)?" 2>/dev/null || semanage fcontext -m -t httpd_sys_content_t "$DIR/logros(/.*)?" || true
  restorecon -R "$DIR/logros" || true
fi
if systemctl is-active --quiet firewalld; then
  firewall-cmd -q --permanent --add-service=http --add-service=https --add-port="$HTTPS_PORT/tcp"
  firewall-cmd -q --reload
fi

paso "Arrancando"
systemctl daemon-reload
systemctl enable -q --now hangar.service caddy.service hangar-logros.timer
systemctl restart hangar.service caddy.service
systemctl start --no-block hangar-logros.service

sleep 3
if ! systemctl is-active --quiet caddy.service; then
  paso "Caddy no ha arrancado. Esto dice:"
  journalctl -u caddy.service -n 25 --no-pager || true
fi
paso "Listo"
echo "Servidor:          $URL"
echo "Panel de admin:    $URL/_/"
echo "Logros:            $URL/logros/logros.db  (se actualiza cada noche)"
if [ -n "$NUEVA_CLAVE" ]; then
  echo
  echo "Cuenta del panel:  $ADMIN_EMAIL"
  echo "Contraseña:        $NUEVA_CLAVE"
  echo "Guárdala: no se vuelve a mostrar. Puedes cambiarla en el panel."
fi
echo
echo "Si la web no abre en un par de minutos, abre los puertos 80 y $HTTPS_PORT en el panel de Raiola (cortafuegos externo)."
echo "En GitHub, la variable HANGAR_SERVER tiene que ser: $URL"
systemctl --no-pager --lines=0 status hangar.service caddy.service | grep -E 'Active:|●' || true
