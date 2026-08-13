#!/usr/bin/env bash
#
# poll-cerbo.sh — poll battery cell-voltage/current D-Bus values from a
# Victron Cerbo GX over SSH and log them locally. Runs entirely on the
# machine you execute it from (e.g. your Mac) — nothing is written to
# the Cerbo's own storage, it's only asked to read D-Bus values.
#
# PREREQUISITES on the Cerbo:
#   Remote Console -> Settings -> General -> Access Level: Superuser,
#   then enable "SSH on LAN". Note the Cerbo's IP/hostname.
#
# BEFORE FIRST USE, discover the exact battery D-Bus service name
# (differs per n-BMS driver/instance) — run once:
#   ssh root@<cerbo-host> "dbus -y | grep -i battery"
# and pass whatever it prints as the second argument below. Cross-check
# the paths used here (System/MaxCellVoltage etc.) against dbus-spy on
# the actual system — see ../dbus-paths.md, these are not yet verified
# on this specific n-BMS integration.
#
# USAGE:
#   ./poll-cerbo.sh <cerbo-host> <battery-dbus-service> [interval-seconds] [output.csv]
#
# EXAMPLE:
#   ./poll-cerbo.sh 192.168.1.50 com.victronenergy.battery.socketcan_can0 2
#
# Stop with Ctrl+C. Re-run the same command later to start a fresh log
# (pass an explicit output filename if you want to keep appending to one).

set -euo pipefail

CERBO_HOST="${1:?usage: poll-cerbo.sh <cerbo-host> <battery-dbus-service> [interval] [output.csv]}"
BATTERY_SVC="${2:?missing battery D-Bus service name — discover via: ssh root@<host> \"dbus -y | grep -i battery\"}"
INTERVAL="${3:-2}"
OUT="${4:-cerbo-log-$(date +%Y%m%d-%H%M%S).csv}"

# SSH connection multiplexing: reuse one authenticated connection for
# every poll instead of a fresh handshake each cycle.
SSH_SOCKET="/tmp/cerbo-ssh-$$.sock"
SSH_OPTS=(-o ControlMaster=auto -o ControlPersist=600 -o ControlPath="$SSH_SOCKET")
cleanup() { ssh "${SSH_OPTS[@]}" -O exit "root@${CERBO_HOST}" 2>/dev/null || true; }
trap cleanup EXIT

echo "Logging to $OUT every ${INTERVAL}s against ${BATTERY_SVC} on ${CERBO_HOST}. Ctrl+C to stop."
echo "timestamp,max_cell_v,min_cell_v,max_cell_id,min_cell_id,dc_current_a,charge_current_limit_a,soc_pct" > "$OUT"

# warm up the multiplexed connection once
ssh "${SSH_OPTS[@]}" "root@${CERBO_HOST}" true

while true; do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # single remote round-trip per cycle: query everything at once
  line=$(ssh "${SSH_OPTS[@]}" "root@${CERBO_HOST}" "
    echo \"\$(dbus -y ${BATTERY_SVC} /System/MaxCellVoltage GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /System/MinCellVoltage GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /System/MaxVoltageCellId GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /System/MinVoltageCellId GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /Dc/0/Current GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /Info/ChargeCurrentLimit GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /Soc GetValue 2>/dev/null)\"
  " 2>/dev/null) || { echo "$ts,ERROR,,,,,," >> "$OUT"; sleep "$INTERVAL"; continue; }

  echo "$ts,$line" >> "$OUT"
  sleep "$INTERVAL"
done
