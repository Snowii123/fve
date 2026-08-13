#!/usr/bin/env bash
#
# poll-cerbo.sh — poll battery + grid + AC-coupled PV D-Bus values from a
# Victron Cerbo GX over SSH and log them locally. Runs entirely on the
# machine you execute it from (e.g. your Mac) — nothing is written to
# the Cerbo's own storage, it's only asked to read D-Bus values.
#
# READ-ONLY, VERIFIED: every call below uses GetValue, which takes no
# argument and cannot write anything. Writing requires the separate
# SetValue method with an explicit value argument (e.g.
# `dbus -y <service> <path> SetValue %1`), which does not appear
# anywhere in this script. Confirmed against the official Venus OS
# command line manual and the com.victronenergy.BusItem interface
# definition in victronenergy/velib_python (see fronius/README.md
# for sources).
#
# PREREQUISITES on the Cerbo:
#   Remote Console -> Settings -> General -> Access Level: Superuser,
#   then "Set root password" (min 6 chars) and enable "SSH on LAN".
#   Note: the root password is reset on every Venus OS firmware update
#   (it lives on the rootfs, which gets replaced) — you'll need to set
#   it again after an update.
#
# SERVICE NAMES confirmed on this system via `dbus -y` on 13.8.2026:
#   battery: com.victronenergy.battery.socketcan_can1
#     (single service for the whole pack — the n-BMS presents both
#     parallel 16S strings as one unified battery to Venus OS, so
#     MaxCellVoltage/MinCellVoltage already span all 32 cells combined)
#   grid meter: com.victronenergy.grid.cgwacs_ttyUSB0_mb1
#   PV inverter (Fronius): com.victronenergy.pvinverter.pv_44_2366585
# If any of these change (different CAN bus, different port), rediscover
# with: ssh root@<cerbo-host> "dbus -y" and pass the new value as an
# argument below.
#
# USAGE:
#   ./poll-cerbo.sh <cerbo-host> [interval-seconds] [output.csv] [battery-svc] [grid-svc] [pv-svc]
#
# EXAMPLE (first run — measure real achievable cycle time, no sleep):
#   ./poll-cerbo.sh 192.168.2.188 0
#   # let it run ~30-60s, Ctrl+C, then look at the poll_duration_s column
#   # in the CSV to see the real floor on this network/hardware before
#   # picking an interval for a longer unattended logging run.
#
# Stop with Ctrl+C. Re-run the same command later to start a fresh log
# (pass an explicit output filename if you want to keep appending to one).

set -euo pipefail

CERBO_HOST="${1:?usage: poll-cerbo.sh <cerbo-host> [interval] [output.csv] [battery-svc] [grid-svc] [pv-svc]}"
INTERVAL="${2:-1}"
OUT="${3:-cerbo-log-$(date +%Y%m%d-%H%M%S).csv}"
BATTERY_SVC="${4:-com.victronenergy.battery.socketcan_can1}"
GRID_SVC="${5:-com.victronenergy.grid.cgwacs_ttyUSB0_mb1}"
PV_SVC="${6:-com.victronenergy.pvinverter.pv_44_2366585}"

# SSH connection multiplexing: reuse one authenticated connection for
# every poll instead of a fresh handshake each cycle.
SSH_SOCKET="/tmp/cerbo-ssh-$$.sock"
SSH_OPTS=(-o ControlMaster=auto -o ControlPersist=600 -o ControlPath="$SSH_SOCKET")
cleanup() { ssh "${SSH_OPTS[@]}" -O exit "root@${CERBO_HOST}" 2>/dev/null || true; }
trap cleanup EXIT

HEADER="timestamp,poll_duration_s,max_cell_v,min_cell_v,max_cell_id,min_cell_id,dc_current_a,charge_current_limit_a,soc_pct,grid_l1_w,grid_l2_w,grid_l3_w,pv_l1_w,pv_l2_w,pv_l3_w,pv_total_w"

echo "Logging to $OUT every ${INTERVAL}s on ${CERBO_HOST}."
echo "  battery: $BATTERY_SVC"
echo "  grid:    $GRID_SVC"
echo "  pv:      $PV_SVC"
echo "Ctrl+C to stop."
echo "$HEADER" > "$OUT"

# warm up the multiplexed connection once (asks for a login, first time only)
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
\$(dbus -y ${GRID_SVC} /Ac/L1/Power GetValue 2>/dev/null),\
\$(dbus -y ${GRID_SVC} /Ac/L2/Power GetValue 2>/dev/null),\
\$(dbus -y ${GRID_SVC} /Ac/L3/Power GetValue 2>/dev/null),\
\$(dbus -y ${PV_SVC} /Ac/L1/Power GetValue 2>/dev/null),\
\$(dbus -y ${PV_SVC} /Ac/L2/Power GetValue 2>/dev/null),\
\$(dbus -y ${PV_SVC} /Ac/L3/Power GetValue 2>/dev/null),\
\$(dbus -y ${PV_SVC} /Ac/Power GetValue 2>/dev/null)\"
  " 2>/dev/null) || { echo "$ts,,ERROR,,,,,,,,,,,,," >> "$OUT"; sleep "$INTERVAL"; continue; }

  t_end=$(date +%s.%N)
  dur=$(awk -v a="$t_start" -v b="$t_end" 'BEGIN { printf "%.2f", b - a }')

  echo "$ts,$dur,$line" >> "$OUT"
  sleep "$INTERVAL"
done
