#!/bin/bash
set -e

PTEMPDIR="$1"
PLUGIN_FOLDER="$3"
PVERSION="$4"
LB_HOME="${5:-${LBHOMEDIR:-/opt/loxberry}}"

DATA_DIR="${LB_HOME}/data/plugins/${PLUGIN_FOLDER}"

mkdir -p "${LB_HOME}/log/plugins/${PLUGIN_FOLDER}" "${DATA_DIR}" || true

chmod +x "${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/schulferien_daemon.pl" 2>/dev/null || true
chmod +x "${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/restart_daemon.sh" 2>/dev/null || true
chmod +x "${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/restore_user_data.sh" 2>/dev/null || true
chmod +x "${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/refresh_state.pl" 2>/dev/null || true
chmod +x "${LB_HOME}/webfrontend/htmlauth/plugins/${PLUGIN_FOLDER}/index.cgi" 2>/dev/null || true

RESTORE="${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/restore_user_data.sh"
if [ -x "${RESTORE}" ]; then
  bash "${RESTORE}" "${PTEMPDIR}" "${PLUGIN_FOLDER}" "${LB_HOME}" || true
fi

touch "${LB_HOME}/log/plugins/${PLUGIN_FOLDER}/schulferien.log" \
      "${DATA_DIR}/schulferien.log" 2>/dev/null || true
chown -R loxberry:loxberry "${LB_HOME}/log/plugins/${PLUGIN_FOLDER}" \
                            "${DATA_DIR}" 2>/dev/null || true
chmod -R u+rwX,g+rwX "${DATA_DIR}" 2>/dev/null || true

if perl -MNet::MQTT::Simple -e 'exit 0' 2>/dev/null; then
  echo "$(date -Iseconds 2>/dev/null || date) postinstall: Net::MQTT::Simple available" \
    >> "${DATA_DIR}/schulferien.log" 2>/dev/null || true
else
  echo "Net::MQTT::Simple missing, trying cpanm install..." >&2
  cpanm --notest Net::MQTT::Simple 2>/dev/null || true
fi

chmod +x "${LB_HOME}/system/cron/cron.reboot/${PLUGIN_FOLDER}" 2>/dev/null || true
chmod +x "${LB_HOME}/system/cron/cron.5min/${PLUGIN_FOLDER}" 2>/dev/null || true

REFRESH="${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/refresh_state.pl"
if [ -x "${REFRESH}" ]; then
  /usr/bin/env perl "${REFRESH}" "${LB_HOME}" "${PLUGIN_FOLDER}" \
    >> "${DATA_DIR}/schulferien.log" 2>&1 || true
fi

RESTART="${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/restart_daemon.sh"
if [ -x "${RESTART}" ]; then
  bash "${RESTART}" "${LB_HOME}" "${PLUGIN_FOLDER}" 2>/dev/null || true
fi

echo "$(date -Iseconds 2>/dev/null || date) postinstall: ${PLUGIN_FOLDER} v${PVERSION}" \
  >> "${DATA_DIR}/schulferien.log" 2>/dev/null || true

exit 0
