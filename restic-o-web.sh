#!/usr/bin/env bash
set -euo pipefail

### FLAGS
ALLOW_REMOTE=false
for arg in "$@"; do
  case "$arg" in
    --allow-remote-access)
      ALLOW_REMOTE=true
      ;;
    *)
      ;;
  esac
done

### VERSIONS
RESTIC_VERSION="0.18.1"
RCLONE_VERSION="1.69.1"
BACKREST_VERSION="1.8.0"

INSTALL_BIN="/usr/local/bin"
BACKREST_DIR="/var/lib/backrest"
BACKREST_PORT="9898"

### UTILS
info() { echo "[+] $*"; }
warn() { echo "[!] $*"; }
die()  { echo "[X] $*" >&2; exit 1; }

### ROOT CHECK
[[ $EUID -eq 0 ]] || die "Exécuter ce script en root"

### ARCH
case "$(uname -m)" in
  aarch64|arm64) ARCH="arm64" ;;
  x86_64)        ARCH="amd64" ;;
  *) die "Architecture non supportée" ;;
esac

### APT DEPS
info "Installation dépendances système"
apt update
apt install -y curl unzip ca-certificates fuse

########################################
# RESTIC
########################################
if ! command -v restic >/dev/null; then
  info "Installation Restic ${RESTIC_VERSION}"
  TMP=$(mktemp -d)
  cd "$TMP"
  curl -fLO https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${ARCH}.bz2
  bunzip2 restic_*.bz2
  install -m755 restic_* "${INSTALL_BIN}/restic"
  cd /
  rm -rf "$TMP"
else
  info "Restic déjà installé"
fi

########################################
# RCLONE
########################################
if ! command -v rclone >/dev/null; then
  info "Installation rclone ${RCLONE_VERSION}"
  TMP=$(mktemp -d)
  cd "$TMP"
  curl -fLO https://github.com/rclone/rclone/releases/download/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${ARCH}.zip
  unzip rclone-*.zip
  install -m755 rclone-*/rclone "${INSTALL_BIN}/rclone"
  cd /
  rm -rf "$TMP"
else
  info "rclone déjà installé"
fi

########################################
# BACKREST
########################################
if ! command -v backrest >/dev/null; then
  info "Installation Backrest ${BACKREST_VERSION}"
  TMP=$(mktemp -d)
  cd "$TMP"
  ARCH=arm64
  curl -L -o backrest.tar.gz \
    "https://github.com/garethgeorge/backrest/releases/latest/download/backrest_linux_${ARCH}.tar.gz"

  tar xzf backrest.tar.gz

  chmod +x install.sh
  ./install.sh --allow-remote-access

  cd /
  rm -rf "$TMP"
else
  info "Backrest déjà installé"
fi

########################################
# BACKREST SYSTEMD OVERRIDE
########################################
info "Configuration override systemd Backrest (low priority)"

OVERRIDE_DIR="/etc/systemd/system/backrest.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"

mkdir -p "${OVERRIDE_DIR}"

cat > "${OVERRIDE_FILE}" <<'EOF'
[Service]
User=root
Group=root

Environment=HOME=/root
Environment=XDG_DATA_HOME=/root/.local/share

Nice=19
CPUWeight=10
IOWeight=10
IOSchedulingClass=idle
IOSchedulingPriority=7
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable backrest.service
systemctl restart backrest.service


########################################
# RCLONE CONFIG
########################################
echo
read -rp "Configurer un remote rclone maintenant ? (Nextcloud/WebDAV) [y/N] " ans
if [[ "$ans" =~ ^[yY]$ ]]; then
  info "Lancement de rclone config"
  rclone config
fi

########################################
# RESTIC REPO INIT (OPTIONNEL)
########################################
echo
read -rp "Initialiser un dépôt Restic via rclone maintenant ? [y/N] " ans
if [[ "$ans" =~ ^[yY]$ ]]; then
  read -rp "Nom du remote rclone (ex: nxt) : " RCLONE_REMOTE
  read -rp "Chemin du dépôt (ex: Apps/restic) : " RCLONE_PATH
  export RESTIC_REPOSITORY="rclone:${RCLONE_REMOTE}:${RCLONE_PATH}"
  read -rsp "Mot de passe Restic : " RESTIC_PASSWORD
  echo
  export RESTIC_PASSWORD
  restic init
fi

########################################
# BACKREST SYSTEMD
########################################
info "Configuration service systemd Backrest"

mkdir -p "$BACKREST_DIR"

cat >/etc/systemd/system/backrest.service <<EOF
[Unit]
Description=Backrest Backup UI
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_BIN}/backrest
Environment=BACKREST_DATA_DIR=${BACKREST_DIR}
Environment=BACKREST_PORT=0.0.0.0:${BACKREST_PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now backrest

########################################
# FIREWALL
########################################
if command -v ufw >/dev/null; then
  ufw allow ${BACKREST_PORT}/tcp || true
fi

########################################
# FIN
########################################
IP=$(hostname -I | awk '{print $1}')

echo
echo "--------------------------------------------------"
echo "INSTALLATION TERMINÉE"
echo
echo "Backrest UI : http://${IP}:${BACKREST_PORT}"
echo
echo "Exemple dépôt Restic :"
echo '  rclone:<remote>:<path>'
echo
echo "Restic low priority (manuel) :"
echo '  ionice -c3 nice -n19 restic backup /etc'
echo
echo "Les plans, prune et rétention se configurent dans Backrest"
echo "--------------------------------------------------"
