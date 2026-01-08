#!/usr/bin/env bash
set -euo pipefail

echo "[+] Vérification privilèges root"
if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être exécuté en root"
  exit 1
fi

SERVICE="backrest.service"
BINARIES=(
  "/usr/local/bin/backrest"
  "/usr/bin/backrest"
)
DATA_DIRS=(
  "/var/lib/backrest"
  "/etc/backrest"
  "/opt/backrest"
)
SYSTEMD_DIRS=(
  "/etc/systemd/system/backrest.service.d"
  "/etc/systemd/credentials/backrest.service"
)

BACKREST_PORT=9898

echo "[+] Arrêt et suppression du service systemd"

if systemctl list-unit-files | grep -q "^${SERVICE}"; then
  systemctl stop "$SERVICE" || true
  systemctl disable "$SERVICE" || true
  rm -f "/etc/systemd/system/$SERVICE"
fi

echo "[+] Suppression overrides et credentials systemd"
for d in "${SYSTEMD_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    rm -rf "$d"
    echo "    supprimé: $d"
  fi
done

echo "[+] Suppression du binaire Backrest"
for bin in "${BINARIES[@]}"; do
  if [[ -f "$bin" ]]; then
    rm -f "$bin"
    echo "    supprimé: $bin"
  fi
done

echo "[+] Suppression des données Backrest"
for dir in "${DATA_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    rm -rf "$dir"
    echo "    supprimé: $dir"
  fi
done

echo "[+] Nettoyage pare-feu"

if command -v ufw >/dev/null; then
  ufw delete allow ${BACKREST_PORT}/tcp 2>/dev/null || true
fi

if command -v nft >/dev/null; then
  nft list ruleset | grep -q "dport ${BACKREST_PORT}" && \
    nft delete rule inet filter input tcp dport ${BACKREST_PORT} 2>/dev/null || true
fi

echo "[+] Rechargement systemd"
systemctl daemon-reexec
systemctl daemon-reload

echo "--------------------------------------------------"
echo "Backrest a été entièrement supprimé."
echo "--------------------------------------------------"
