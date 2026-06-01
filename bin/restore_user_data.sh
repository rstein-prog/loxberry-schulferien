#!/bin/bash

PTEMPDIR="$1"
PLUGIN_FOLDER="$2"
LB_HOME="${3:-${LBHOMEDIR:-/opt/loxberry}}"

DATA_DIR="${LB_HOME}/data/plugins/${PLUGIN_FOLDER}"
CONFIG_DIR="${LB_HOME}/config/plugins/${PLUGIN_FOLDER}"
LOG_FILE="${DATA_DIR}/schulferien.log"

log_line() {
  echo "$(date -Iseconds 2>/dev/null || date) restore: $1" >> "${LOG_FILE}" 2>/dev/null || true
  echo "<INFO> Schulferien: $1"
}

mkdir -p "${DATA_DIR}" "${CONFIG_DIR}" 2>/dev/null || true

restore_from_dir() {
  local label="$1"
  local src="$2"
  [ -d "${src}" ] || return 0

  if [ -d "${src}/data" ]; then
    cp -a "${src}/data/." "${DATA_DIR}/" 2>/dev/null || true
    log_line "restored ${label}/data -> data/plugins/${PLUGIN_FOLDER}"
  fi

  if [ -f "${src}/config/schulferien.cfg" ] && [ ! -f "${DATA_DIR}/schulferien.cfg" ]; then
    cp -f "${src}/config/schulferien.cfg" "${DATA_DIR}/schulferien.cfg" 2>/dev/null || true
    log_line "restored legacy schulferien.cfg from ${label}/config"
  fi
}

restore_missing_from_dir() {
  local label="$1"
  local src="$2"
  [ -d "${src}/data" ] || return 0

  local item base
  for item in "${src}/data"/*; do
    [ -e "${item}" ] || continue
    base="$(basename "${item}")"
    [ -e "${DATA_DIR}/${base}" ] && continue
    cp -a "${item}" "${DATA_DIR}/" 2>/dev/null || true
    log_line "restored missing ${base} from ${label}/data"
  done

  if [ -f "${src}/config/schulferien.cfg" ] && [ ! -f "${DATA_DIR}/schulferien.cfg" ]; then
    cp -f "${src}/config/schulferien.cfg" "${DATA_DIR}/schulferien.cfg" 2>/dev/null || true
    log_line "restored legacy schulferien.cfg from ${label}/config"
  fi
}

if [ -n "${PTEMPDIR}" ]; then
  restore_from_dir "preupgrade backup" "/tmp/${PTEMPDIR}_schulferien_userdata"
  restore_missing_from_dir "legacy upgrade dir" "/tmp/${PTEMPDIR}_upgrade"
fi

if [ -f "${CONFIG_DIR}/schulferien.cfg" ] && [ ! -f "${DATA_DIR}/schulferien.cfg" ]; then
  cp -f "${CONFIG_DIR}/schulferien.cfg" "${DATA_DIR}/schulferien.cfg" 2>/dev/null || true
  log_line "migrated config/schulferien.cfg to data dir"
fi

exit 0
