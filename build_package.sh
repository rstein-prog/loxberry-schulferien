#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${ROOT_DIR}/dist"
VERSION="$(awk -F= '/^VERSION=/{print $2}' "${ROOT_DIR}/plugin.cfg")"
PLUGIN_NAME="$(awk -F= '
  /^\[PLUGIN\]/{in_plugin=1; next}
  /^\[/{in_plugin=0}
  in_plugin && /^NAME=/{print $2; exit}
' "${ROOT_DIR}/plugin.cfg")"
ARCHIVE_NAME="${PLUGIN_NAME}_${VERSION}.zip"
ARCHIVE_PATH="${OUT_DIR}/${ARCHIVE_NAME}"

mkdir -p "${OUT_DIR}"
rm -f "${ARCHIVE_PATH}"

cd "${ROOT_DIR}"

if command -v python3 >/dev/null 2>&1 && [ -f "${ROOT_DIR}/tools/generate_icons.py" ]; then
  python3 "${ROOT_DIR}/tools/generate_icons.py" || true
fi

zip -r "${ARCHIVE_PATH}" \
  plugin.cfg \
  README.md \
  preinstall.sh \
  preupgrade.sh \
  postinstall.sh \
  postupgrade.sh \
  postroot.sh \
  bin \
  config \
  icons \
  dpkg \
  cron \
  templates \
  webfrontend \
  daemon

echo "Created ${ARCHIVE_PATH}"
