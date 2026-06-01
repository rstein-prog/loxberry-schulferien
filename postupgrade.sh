#!/bin/bash

PTEMPDIR="$1"
PLUGIN_FOLDER="$3"
LB_HOME="${5:-${LBHOMEDIR:-/opt/loxberry}}"
RESTORE="${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/restore_user_data.sh"

DATA_DIR="${LB_HOME}/data/plugins/${PLUGIN_FOLDER}"
mkdir -p "${DATA_DIR}" 2>/dev/null || true

if [ -x "${RESTORE}" ]; then
  bash "${RESTORE}" "${PTEMPDIR}" "${PLUGIN_FOLDER}" "${LB_HOME}" || true
fi

REFRESH="${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/refresh_state.pl"
if [ -x "${REFRESH}" ]; then
  /usr/bin/env perl "${REFRESH}" "${LB_HOME}" "${PLUGIN_FOLDER}" \
    >> "${DATA_DIR}/schulferien.log" 2>&1 || true
fi

rm -rf "/tmp/${PTEMPDIR}_schulferien_userdata" 2>/dev/null || true

exit 0
