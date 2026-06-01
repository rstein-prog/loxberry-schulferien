#!/bin/bash

PTEMPDIR="$1"
PDIR="$3"
LB_HOME="${5:-${LBHOMEDIR:-/opt/loxberry}}"

BACKUP="/tmp/${PTEMPDIR}_schulferien_userdata"
DATA_SRC="${LB_HOME}/data/plugins/${PDIR}"
CONFIG_SRC="${LB_HOME}/config/plugins/${PDIR}"

rm -rf "${BACKUP}" 2>/dev/null || true
mkdir -p "${BACKUP}/data" "${BACKUP}/config" || exit 0

if [ -d "${DATA_SRC}" ]; then
  cp -a "${DATA_SRC}/." "${BACKUP}/data/" 2>/dev/null || true
  echo "<INFO> Schulferien: backed up data/plugins/${PDIR} (settings, cached state)"
fi

if [ -d "${CONFIG_SRC}" ]; then
  cp -a "${CONFIG_SRC}/." "${BACKUP}/config/" 2>/dev/null || true
  echo "<INFO> Schulferien: backed up config/plugins/${PDIR}"
fi

exit 0
