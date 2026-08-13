#!/usr/bin/env bash
#
# poll-cerbo.sh — poll battery + grid + AC-coupled PV D-Bus values from a
# Victron Cerbo GX over SSH and log them locally. Runs entirely on the
# machine you execute it from (e.g. your Mac) — nothing is written to
# the Cerbo's own storage. Each cycle streams a small Python script over
# SSH stdin into a `python3` process on the Cerbo (nothing saved there —
# the process exists only for the duration of that one SSH call); the
# script opens ONE D-Bus connection and reads every value through it,
# instead of the earlier version's approach of spawning the `dbus -y`
# CLI tool 15 separate times per cycle (measured at ~16s/cycle — each
# `dbus -y` invocation pays its own process-startup cost; a normal D-Bus
# round-trip should be tens of milliseconds, not ~1s, see sources below).
#
# READ-ONLY, VERIFIED: the Python script only ever calls the D-Bus
# `com.victronenergy.BusItem.GetValue` method (no arguments, a pure
# read). Writing uses the separate `SetValue(newvalue)` method, which
# requires an explicit value argument and is never called anywhere here.
# Sources:
#   - Venus OS Operational Command Line Manual:
#     https://www.victronenergy.com/live/open_source:ccgx:commandline?do=export_pdf&rev=1615037933
#   - velib_python vedbus.py (defines the BusItem interface):
#     https://github.com/victronenergy/velib_python/blob/master/vedbus.py
#   - D-Bus round-trip performance expectations (tens of ms is normal):
#     https://communityarchive.victronenergy.com/questions/237145/venus-gx-d-bus-round-trip-time-too-high.html
#   - Correct CCL path is /Info/MaxChargeCurrent, not /Info/ChargeCurrentLimit
#     (the earlier version of this script used the wrong path):
#     https://github.com/victronenergy/dbus-systemcalc-py/blob/master/delegates/dvcc.py
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
#     parallel 16S strings as one unified battery to Venus OS; the
#     max/min cell IDs it reports identify which 16-cell "Pack" the
#     extreme is in, e.g. "Pack-01#", NOT the individual cell number
#     within that pack — for that you need the n-BMS's own app)
#   grid meter: com.victronenergy.grid.cgwacs_ttyUSB0_mb1
#   PV inverter (Fronius): com.victronenergy.pvinverter.pv_44_2366585
# If any of these change, rediscover with:
#   ssh root@<cerbo-host> "dbus -y"
# and pass the new value as an argument below.
#
# USAGE:
#   ./poll-cerbo.sh <cerbo-host> [interval-seconds] [output.csv] [battery-svc] [grid-svc] [pv-svc]
#
# EXAMPLE (first run — measure real achievable cycle time, no sleep):
#   ./poll-cerbo.sh 192.168.2.188 0
#   # let it run ~30-60s, Ctrl+C, then check the poll_duration_s column.
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

HEADER="timestamp,poll_duration_s,max_cell_v,min_cell_v,max_cell_id,min_cell_id,dc_current_a,charge_current_a,soc_pct,grid_l1_w,grid_l2_w,grid_l3_w,pv_l1_w,pv_l2_w,pv_l3_w,pv_total_w"

echo "Logging to $OUT every ${INTERVAL}s on ${CERBO_HOST}."
echo "  battery: $BATTERY_SVC"
echo "  grid:    $GRID_SVC"
echo "  pv:      $PV_SVC"
echo "Ctrl+C to stop."
echo "$HEADER" > "$OUT"

# warm up the multiplexed connection once (asks for a login, first time only)
ssh "${SSH_OPTS[@]}" "root@${CERBO_HOST}" true

# Python payload: one D-Bus connection, reads every path, prints a single
# comma-separated line. Fed over SSH stdin each cycle — never written to
# a file on the Cerbo. Takes battery/grid/pv service names as argv so the
# script itself doesn't need editing if a service name changes.
read -r -d '' PY_SCRIPT <<'PYEOF' || true
import dbus, sys
bus = dbus.SystemBus()
BATTERY, GRID, PV = sys.argv[1], sys.argv[2], sys.argv[3]
paths = [
    (BATTERY, "/System/MaxCellVoltage"),
    (BATTERY, "/System/MinCellVoltage"),
    (BATTERY, "/System/MaxVoltageCellId"),
    (BATTERY, "/System/MinVoltageCellId"),
    (BATTERY, "/Dc/0/Current"),
    (BATTERY, "/Info/MaxChargeCurrent"),
    (BATTERY, "/Soc"),
    (GRID, "/Ac/L1/Power"),
    (GRID, "/Ac/L2/Power"),
    (GRID, "/Ac/L3/Power"),
    (PV, "/Ac/L1/Power"),
    (PV, "/Ac/L2/Power"),
    (PV, "/Ac/L3/Power"),
    (PV, "/Ac/Power"),
]
out = []
for service, path in paths:
    try:
        obj = bus.get_object(service, path)
        val = obj.GetValue(dbus_interface="com.victronenergy.BusItem")
        out.append(str(val))
    except Exception:
        out.append("")
print(",".join(out))
PYEOF

while true; do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  t_start=$(date +%s.%N)

  line=$(ssh "${SSH_OPTS[@]}" "root@${CERBO_HOST}" python3 - "$BATTERY_SVC" "$GRID_SVC" "$PV_SVC" <<< "$PY_SCRIPT" 2>/dev/null) \
    || { echo "$ts,,ERROR,,,,,,,,,,,,," >> "$OUT"; sleep "$INTERVAL"; continue; }

  t_end=$(date +%s.%N)
  dur=$(awk -v a="$t_start" -v b="$t_end" 'BEGIN { printf "%.2f", b - a }')

  echo "$ts,$dur,$line" >> "$OUT"
  sleep "$INTERVAL"
done
