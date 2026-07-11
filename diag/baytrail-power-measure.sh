#!/bin/sh
# baytrail-power-measure.sh — measure real battery drain via the ACPI fuel gauge
# (works even though charging/AC detection is firmware-broken). Run UNPLUGGED.
#
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < baytrail-power-measure.sh [SECONDS]
# Default window 180s. Longer = more accurate. Keep the screen in its normal
# use state (don't touch it) for a representative idle number, or drive it for a
# load number. Run once before installing iconia-powertune and once after to
# compare.
set -u
WIN=${1:-180}
B=/sys/class/power_supply/BATC
NOMINAL_V=3.7   # voltage_now reads 0 on this board; nominal for a watt estimate

rd(){ cat "$B/$1" 2>/dev/null; }

online=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)
[ "$online" = "1" ] && echo "WARN: ADP1.online=1 (won't happen here — firmware bug) "
case "$(rd status)" in
  Discharging) ;;
  *) echo "NOTE: status=$(rd status). For a DRAIN number, UNPLUG the charger first.";;
esac

full_uah=$(rd charge_full)                 # µAh
c0=$(rd charge_now); cap0=$(rd capacity); i0=$(rd current_now)
t0=$(date +%s)
echo "t0: charge_now=${c0}uAh  capacity=${cap0}%  current_now=${i0}uA"
echo "measuring for ${WIN}s (leave it alone)..."
sleep "$WIN"
c1=$(rd charge_now); cap1=$(rd capacity); i1=$(rd current_now)
t1=$(date +%s)
dt=$((t1 - t0))
echo "t1: charge_now=${c1}uAh  capacity=${cap1}%  current_now=${i1}uA  (dt=${dt}s)"

# Average current from the charge delta (µAh over dt seconds -> mA).
#   mA = (dC_uAh) / (dt_s/3600) / 1000
awk -v c0="$c0" -v c1="$c1" -v dt="$dt" -v full="$full_uah" \
    -v cap0="$cap0" -v cap1="$cap1" -v v="$NOMINAL_V" -v i1="$i1" 'BEGIN{
  dC = c0 - c1;                       # µAh consumed (positive when draining)
  hrs = dt/3600.0;
  mA  = (dC/1000.0)/hrs;              # average mA over the window
  inst_mA = i1/1000.0;
  W   = (mA/1000.0)*v;                # nominal watts
  runtime_h = (full/1000.0)/mA;       # full(µAh)->mAh / mA
  pph = (cap0-cap1)/hrs;             # %/hour
  printf "\n===== DRAIN =====\n";
  printf "avg draw over window : %.0f mA  (~%.2f W @ %.1fV nominal)\n", mA, W, v;
  printf "instantaneous now    : %.0f mA\n", inst_mA;
  printf "capacity change      : %d%% -> %d%%  (%.1f %%/hour)\n", cap0, cap1, pph;
  printf "est. runtime from full: %.1f h  (full=%.2f Ah)\n", runtime_h, full/1e6;
  if (dC<=0) printf "NOTE: no charge drop measured — likely plugged in or window too short.\n";
}'
