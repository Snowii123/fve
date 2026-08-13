#!/usr/bin/env bash
#
# poll-cerbo.sh — poll battery + grid + AC-coupled PV + vebus D-Bus values
# from a Victron Cerbo GX over SSH and log them locally. Runs entirely on
# the machine you execute it from (e.g. your Mac) — nothing is written to
# the Cerbo's own storage. Each cycle streams a small Python script over
# SSH stdin into a `python3` process on the Cerbo (nothing saved there —
# the process exists only for the duration of that one SSH call).
#
# BATTERY VALUES: read via a single GetValue on the battery service's
# root path "/" — the SHEnergy CAN-SMARTBMS-BAT (driver: can-bus-bms)
# on this system exports its entire state as one nested dict this way.
# Individual per-path queries (e.g. .../Alarms/LowVoltage GetValue)
# returned empty for the Alarms/* fields on this driver even though
# they're genuinely present (all 0/OK) in the root dump — this driver
# apparently only populates them at the root-item level, not as
# separately addressable objects. The root-dump approach sidesteps
# that and is simpler/faster than the previous 25-separate-paths
# version besides.
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
#   - vebus /State value meanings (0=Off, 2=Fault, 3=Bulk, 4=Absorption,
#     5=Float, 252=External control, etc.):
#     https://community.victronenergy.com/questions/14089/ve-bus-state-codes.html
#
# WHY THESE FIELDS: designed for two purposes — (1) catching the exact
# voltage/current at which the pack trips during top-end calibration,
# and (2) the same for the Fronius power-mismatch buffer work later
# (see ../../fronius/README.md). Info/MaxChargeVoltage and
# Info/BatteryLowVoltage are the BMS's own commanded charge/discharge
# voltage targets — the closest thing we have to real V_hard/floor
# numbers instead of estimates, see checklist.md.
#
# PREREQUISITES on the Cerbo:
#   Remote Console -> Settings -> General -> Access Level: Superuser,
#   then "Set root password" (min 6 chars) and enable "SSH on LAN".
#   Note: the root password is reset on every Venus OS firmware update.
#
# SERVICE NAMES confirmed on this system via `dbus -y` on 13.8.2026:
#   battery: com.victronenergy.battery.socketcan_can1
#   grid meter: com.victronenergy.grid.cgwacs_ttyUSB0_mb1
#   PV inverter (Fronius): com.victronenergy.pvinverter.pv_44_2366585
#   vebus (MultiPlus-II cluster): com.victronenergy.vebus.ttyS4
# If any of these change, rediscover with: ssh root@<cerbo-host> "dbus -y"
#
# USAGE:
#   ./poll-cerbo.sh <cerbo-host> [interval-seconds] [output.csv] [battery-svc] [grid-svc] [pv-svc] [vebus-svc]
#
# EXAMPLE (first run — measure real achievable cycle time, no sleep):
#   ./poll-cerbo.sh 192.168.2.188 0
#   # let it run ~30-60s, Ctrl+C, then check the poll_duration_s column.
#
# Stop with Ctrl+C. Re-run the same command later to start a fresh log
# (pass an explicit output filename if you want to keep appending to one).

set -euo pipefail

CERBO_HOST="${1:?usage: poll-cerbo.sh <cerbo-host> [interval] [output.csv] [battery-svc] [grid-svc] [pv-svc] [vebus-svc]}"
INTERVAL="${2:-1}"
OUT="${3:-cerbo-log-$(date +%Y%m%d-%H%M%S).csv}"
BATTERY_SVC="${4:-com.victronenergy.battery.socketcan_can1}"
GRID_SVC="${5:-com.victronenergy.grid.cgwacs_ttyUSB0_mb1}"
PV_SVC="${6:-com.victronenergy.pvinverter.pv_44_2366585}"
VEBUS_SVC="${7:-com.victronenergy.vebus.ttyS4}"

SSH_SOCKET="/tmp/cerbo-ssh-$$.sock"
SSH_OPTS=(-o ControlMaster=auto -o ControlPersist=600 -o ControlPath="$SSH_SOCKET")
cleanup() { ssh "${SSH_OPTS[@]}" -O exit "root@${CERBO_HOST}" 2>/dev/null || true; }
trap cleanup EXIT

HEADER="timestamp,poll_duration_s,pack_voltage_v,max_cell_v,min_cell_v,max_cell_id,min_cell_id,dc_current_a,charge_current_limit_a,discharge_current_limit_a,max_charge_voltage_v,low_voltage_cutoff_v,battery_temp_c,max_cell_temp_c,min_cell_temp_c,soc_pct,soh_pct,alarm_low_voltage,alarm_high_cell_voltage,alarm_cell_imbalance,alarm_charge_blocked,alarm_discharge_blocked,alarm_high_charge_current,alarm_high_discharge_current,alarm_high_temperature,alarm_low_temperature,alarm_high_charge_temp,alarm_low_charge_temp,alarm_internal_failure,vebus_state,grid_l1_w,grid_l2_w,grid_l3_w,pv_l1_w,pv_l2_w,pv_l3_w,pv_total_w"

echo "Logging to $OUT every ${INTERVAL}s on ${CERBO_HOST}."
echo "  battery: $BATTERY_SVC"
echo "  grid:    $GRID_SVC"
echo "  pv:      $PV_SVC"
echo "  vebus:   $VEBUS_SVC"
echo "Ctrl+C to stop."
echo "$HEADER" > "$OUT"

ssh "${SSH_OPTS[@]}" "root@${CERBO_HOST}" true

read -r -d '' PY_SCRIPT <<'PYEOF' || true
import dbus, sys
bus = dbus.SystemBus()
BATTERY, GRID, PV, VEBUS = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def get(service, path):
    try:
        obj = bus.get_object(service, path)
        return obj.GetValue(dbus_interface="com.victronenergy.BusItem")
    except Exception:
        return None

battery_root = get(BATTERY, "/")
if not isinstance(battery_root, dict):
    battery_root = {}

def bkey(k):
    v = battery_root.get(k)
    if v is None or v == []:
        return ""
    # dbus.Byte (used for the Alarms/* 0/1/2 flags on this driver) prints
    # as an invisible control character via str() instead of its numeric
    # value — found by ../scripts/debug_alarms.sh on 13.8.2026. Cast
    # through int() to get "0"/"1"/"2" instead of a blank field.
    if isinstance(v, dbus.Byte):
        return str(int(v))
    return str(v)

battery_fields = [
    bkey("Dc/0/Voltage"),
    bkey("System/MaxCellVoltage"),
    bkey("System/MinCellVoltage"),
    bkey("System/MaxVoltageCellId"),
    bkey("System/MinVoltageCellId"),
    bkey("Dc/0/Current"),
    bkey("Info/MaxChargeCurrent"),
    bkey("Info/MaxDischargeCurrent"),
    bkey("Info/MaxChargeVoltage"),
    bkey("Info/BatteryLowVoltage"),
    bkey("Dc/0/Temperature"),
    bkey("System/MaxCellTemperature"),
    bkey("System/MinCellTemperature"),
    bkey("Soc"),
    bkey("Soh"),
    bkey("Alarms/LowVoltage"),
    bkey("Alarms/HighCellVoltage"),
    bkey("Alarms/CellImbalance"),
    bkey("Alarms/ChargeBlocked"),
    bkey("Alarms/DischargeBlocked"),
    bkey("Alarms/HighChargeCurrent"),
    bkey("Alarms/HighDischargeCurrent"),
    bkey("Alarms/HighTemperature"),
    bkey("Alarms/LowTemperature"),
    bkey("Alarms/HighChargeTemperature"),
    bkey("Alarms/LowChargeTemperature"),
    bkey("Alarms/InternalFailure"),
]

other_paths = [
    (VEBUS, "/State"),
    (GRID, "/Ac/L1/Power"),
    (GRID, "/Ac/L2/Power"),
    (GRID, "/Ac/L3/Power"),
    (PV, "/Ac/L1/Power"),
    (PV, "/Ac/L2/Power"),
    (PV, "/Ac/L3/Power"),
    (PV, "/Ac/Power"),
]
other_fields = []
for service, path in other_paths:
    v = get(service, path)
    other_fields.append("" if v is None else str(v))

print(",".join(battery_fields + other_fields))
PYEOF

while true; do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  t_start=$(date +%s.%N)

  line=$(ssh "${SSH_OPTS[@]}" "root@${CERBO_HOST}" python3 - "$BATTERY_SVC" "$GRID_SVC" "$PV_SVC" "$VEBUS_SVC" <<< "$PY_SCRIPT" 2>/dev/null) \
    || { echo "$ts,,ERROR" >> "$OUT"; sleep "$INTERVAL"; continue; }

  t_end=$(date +%s.%N)
  dur=$(awk -v a="$t_start" -v b="$t_end" 'BEGIN { printf "%.2f", b - a }')

  echo "$ts,$dur,$line" >> "$OUT"
  sleep "$INTERVAL"
done
