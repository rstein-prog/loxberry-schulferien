#!/bin/bash

PLUGIN_FOLDER="$(basename "$0")"
LB_HOME="${1:-${LBHOMEDIR:-/opt/loxberry}}"
DAEMON="${LB_HOME}/bin/plugins/${PLUGIN_FOLDER}/schulferien_daemon.pl"
LOG="${LB_HOME}/log/plugins/${PLUGIN_FOLDER}/schulferien.log"

if [ -f "$DAEMON" ]; then
  pkill -f "schulferien_daemon.pl" 2>/dev/null || true
  sleep 1
  mkdir -p "${LB_HOME}/log/plugins/${PLUGIN_FOLDER}" 2>/dev/null || true
  nohup /usr/bin/env perl "$DAEMON" >> "$LOG" 2>&1 &
  echo "Daemon (re)started."
fi
