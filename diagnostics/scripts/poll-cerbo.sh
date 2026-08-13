#!/usr/bin/env bash
#
# poll-cerbo.sh — poll battery + grid + AC-coupled PV D-Bus values from a
# Victron Cerbo GX over SSH and log them locally. Runs entirely on the
# machine you execute it from (e.g. your Mac) — nothing is written to
# the Cerbo's own storage, it's only asked to read D-Bus values (every
# call below is GetValue — a read; SetValue, which would write, is never
# used anywhere in this script).
#
# PREREQUISITES on the Cerbo:
#   Remote Console -> Settings -> General -> Access Level: Superuser,
#   then enable "SSH on LAN". Note the Cerbo's IP/hostname.
#
# BEFORE FIRST USE, discover the exact battery D-Bus service name
# (differs per n-BMS driver/instance) — run once:
#   ssh root@<cerbo-host> "dbus -y | grep -i battery"
# and pass whatever it prints as the second argument below. The grid/PV
# paths use com.victronenergy.system, which is a fixed well-known service
# name (no discovery needed) — but the exact L1/L2/L3 sub-paths still
# need cross-checking against dbus-spy on the real system, see
# ../dbus-paths.md. This system is assumed 3-phase (6x MultiPlus-II,
# likely 2 per phase) — if it's actually single-phase, only the L1
# columns will have data and L2/L3 will read empty, which is harmless.
#
# USAGE:
#   ./poll-cerbo.sh <cerbo-host> <battery-dbus-service> [interval-seconds] [output.csv]
#
# EXAMPLE (first run — measure real achievable cycle time, no sleep):
#   ./poll-cerbo.sh 192.168.1.50 com.victronenergy.battery.socketcan_can0 0
#   # let it run ~30-60s, Ctrl+C, then look at the poll_duration_s column
#   # in the CSV to see the real floor on this network/hardware before
#   # picking an interval for a longer unattended logging run.
#
# Stop with Ctrl+C. Re-run the same command later to start a fresh log
# (pass an explicit output filename if you want to keep appending to one).

set -euo pipefail

CERBO_HOST="${1:?usage: poll-cerbo.sh <cerbo-host> <battery-dbus-service> [interval] [output.csv]}"
BATTERY_SVC="${2:?missing battery D-Bus service name — discover via: ssh root@<host> \"dbus -y | grep -i battery\"}"
INTERVAL="${3:-1}"
OUT="${4:-cerbo-log-$(date +%Y%m%d-%H%M%S).csv}"

# SSH connection multiplexing: reuse one authenticated connection for
# every poll instead of a fresh handshake each cycle.
SSH_SOCKET="/tmp/cerbo-ssh-$$.sock"
SSH_OPTS=(-o ControlMaster=auto -o ControlPersist=600 -o ControlPath="$SSH_SOCKET")
cleanup() { ssh "${SSH_OPTS[@]}" -O exit "root@${CERBO_HOST}" 2>/dev/null || true; }
trap cleanup EXIT

HEADER="timestamp,poll_duration_s,max_cell_v,min_cell_v,max_cell_id,min_cell_id,dc_current_a,charge_current_limit_a,soc_pct,grid_l1_w,grid_l2_w,grid_l3_w,pv_ongrid_l1_w,pv_ongrid_l2_w,pv_ongrid_l3_w,dc_battery_power_w"

echo "Logging to $OUT every ${INTERVAL}s against ${BATTERY_SVC} on ${CERBO_HOST}. Ctrl+C to stop."
echo "$HEADER" > "$OUT"

# warm up the multiplexed connection once
ssh "${SSH_OPTS[@]}" "root@${CERBO_HOST}" true

while true; do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  t_start=$(date +%s.%N)

  # single remote round-trip per cycle: query everything at once, all
  # reads (GetValue) — nothing on the Cerbo is written or modified.
  line=$(ssh "${SSH_OPTS[@]}" "root@${CERBO_HOST}" "
    echo \"\$(dbus -y ${BATTERY_SVC} /System/MaxCellVoltage GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /System/MinCellVoltage GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /System/MaxVoltageCellId GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /System/MinVoltageCellId GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /Dc/0/Current GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /Info/ChargeCurrentLimit GetValue 2>/dev/null),\
\$(dbus -y ${BATTERY_SVC} /Soc GetValue 2>/dev/null),\
\$(dbus -y com.victronenergy.system /Ac/Grid/L1/Power GetValue 2>/dev/null),\
\$(dbus -y com.victronenergy.system /Ac/Grid/L2/Power GetValue 2>/dev/null),\
\$(dbus -y com.victronenergy.system /Ac/Grid/L3/Power GetValue 2>/dev/null),\
\$(dbus -y com.victronenergy.system /Ac/PvOnGrid/L1/Power GetValue 2>/dev/null),\
\$(dbus -y com.victronenergy.system /Ac/PvOnGrid/L2/Power GetValue 2>/dev/null),\
\$(dbus -y com.victronenergy.system /Ac/PvOnGrid/L3/Power GetValue 2>/dev/null),\
\$(dbus -y com.victronenergy.system /Dc/Battery/Power GetValue 2>/dev/null)\"
  " 2>/dev/null) || { echo "$ts,,ERROR,,,,,,,,,,,,," >> "$OUT"; sleep "$INTERVAL"; continue; }

  t_end=$(date +%s.%N)
  dur=$(awk -v a="$t_start" -v b="$t_end" 'BEGIN { printf "%.2f", b - a }')

  echo "$ts,$dur,$line" >> "$OUT"
  sleep "$INTERVAL"
done
