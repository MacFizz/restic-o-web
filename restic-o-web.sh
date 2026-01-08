#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# CONFIGURATION
###############################################################################

RESTIC_INSTALL_DIR="/usr/local/bin"
BACKREST_PORT=9898
SERVICE="backrest.service"
SYSTEMD_DIR="/etc/systemd/system"

###############################################################################
# ROOT CHECK
###############################################################################

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

###############################################################################
# ARCHITECTURE
###############################################################################

echo "==> Détection de l’architecture"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  RESTIC_ARCH="amd64" ;;
  aarch64) RESTIC_ARCH="arm64" ;;
  armv7l)  RESTIC_ARCH="arm" ;;
  *)
    echo "Architecture non supportée : $ARCH" >&2
    exit 1
    ;;
esac

###############################################################################
# CLEAN BACKREST (OLD INSTALL)
###############################################################################

echo "==> Suppression d’une installation Backrest existante (si présente)"

if systemctl list-unit-files | grep -q "^${SERVICE}"; then
  systemctl stop "${SERVICE}" || true
  systemctl disable "${SERVICE}" || true
fi

rm -f "${SYSTEMD_DIR}/${SERVICE}"
rm -rf "${SYSTEMD_DIR}/${SERVICE}.d"

if command -v backrest >/dev/null 2>&1; then
  rm -f "$(command -v backrest)"
fi

systemctl daemon-reload

###############################################################################
# RESTIC
###############################################################################

echo "==> Installation de Restic (dernière version GitHub)"

if command -v restic >/dev/null 2>&1; then
  rm -f "$(command -v restic)"
fi

RESTIC_VERSION="$(curl -fsSL https://api.github.com/repos/restic/restic/releases/latest \
  | grep '"tag_name"' | cut -d '"' -f4)"

RESTIC_VERSION_CLEAN="${RESTIC_VERSION#v}"
RESTIC_FILE="restic_${RESTIC_VERSION_CLEAN}_linux_${RESTIC_ARCH}.bz2"
RESTIC_URL="https://github.com/restic/restic/releases/download/${RESTIC_VERSION}/${RESTIC_FILE}"

curl -fsSL "$RESTIC_URL" -o "/tmp/${RESTIC_FILE}"
bunzip2 -f "/tmp/${RESTIC_FILE}"

install -m 0755 "/tmp/restic_${RESTIC_VERSION_CLEAN}_linux_${RESTIC_ARCH}" \
  "${RESTIC_INSTALL_DIR}/restic"

rm -f "/tmp/restic_${RESTIC_VERSION_CLEAN}_linux_${RESTIC_ARCH}"

restic version

###############################################################################
# BACKREST
###############################################################################

echo "==> Installation de Backrest via install.sh"

TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"

BACKREST_VERSION="$(curl -fsSL https://api.github.com/repos/garethgeorge/backrest/releases/latest \
  | grep '"tag_name"' | cut -d '"' -f4)"

BACKREST_TARBALL="backrest_Linux_${RESTIC_ARCH}.tar.gz"
BACKREST_URL="https://github.com/garethgeorge/backrest/releases/download/${BACKREST_VERSION}/${BACKREST_TARBALL}"

curl -fsSL "$BACKREST_URL" -o backrest.tar.gz
tar -xzf backrest.tar.gz

chmod +x install.sh
./install.sh --allow-remote-access

cd /
rm -rf "$TMP_DIR"

systemctl daemon-reload
systemctl enable --now backrest.service

###############################################################################
# FIREWALL
###############################################################################

echo "==> Configuration du pare-feu (si présent)"

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  echo "    UFW actif – ouverture du port ${BACKREST_PORT}/tcp"
  ufw allow "${BACKREST_PORT}/tcp"
elif command -v nft >/dev/null 2>&1; then
  echo "    nftables détecté – ouverture du port ${BACKREST_PORT}/tcp"
  nft list ruleset | grep -q "backrest" || \
    nft add rule inet filter input tcp dport ${BACKREST_PORT} ct state new accept comment \"backrest\"
else
  echo "    Aucun pare-feu géré détecté"
fi

###############################################################################
# TEST CONNECTIVITÉ
###############################################################################

echo "==> Test d’accessibilité Backrest"

HOST_IP="$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')"
BACKREST_URL="http://${HOST_IP}:${BACKREST_PORT}"

echo "    URL testée : ${BACKREST_URL}"

sleep 3

if command -v curl >/dev/null 2>&1; then
  curl -fs "$BACKREST_URL" >/dev/null
elif command -v wget >/dev/null 2>&1; then
  wget -qO- "$BACKREST_URL" >/dev/null
else
  echo "curl ou wget requis pour le test HTTP" >&2
  exit 1
fi

echo "✔ Backrest est accessible depuis le réseau"

###############################################################################
echo "==> Installation terminée avec succès"
