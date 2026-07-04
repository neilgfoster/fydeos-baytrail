#!/bin/sh
# iconia-pwr-rapl.sh — fast SoC power meter via Intel RAPL energy counter.
# Ideal A/B meter for CPU/GPU/uncore-side changes (C-states, governor, services,
# modules, IRQ storms). Does NOT see the backlight rail — use the battery gauge
# for screen-brightness deltas.
#
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-pwr-rapl.sh [WIN_S] [SUB_S] [LABEL]
#   defaults: WIN=18s  SUB=3s   -> 6 interval samples, reports mean/min/max W
set -u
WIN=${1:-18}; SUB=${2:-3}; LABEL=${3:-run}

# Find the package-0 zone dir by name (robust to numbering).
PKG=""
for z in /sys/class/powercap/intel-rapl:*; do
    [ -e "$z/name" ] || continue
    [ "$(cat "$z/name")" = "package-0" ] && PKG="$z" && break
done
[ -n "$PKG" ] || { echo "no package-0 RAPL zone"; exit 1; }
MAXJ=$(cat "$PKG/max_energy_range_uj" 2>/dev/null || echo 0)

rd(){ cat "$PKG/energy_uj"; }
n=$(( WIN / SUB )); [ "$n" -lt 1 ] && n=1
TMP=/tmp/.rapl.$$; : > "$TMP"
e0=$(rd)
i=0
while [ $i -lt $n ]; do
    sleep "$SUB"
    e1=$(rd)
    d=$(( e1 - e0 )); [ $d -lt 0 ] && d=$(( d + MAXJ ))   # handle wrap
    awk -v d="$d" -v s="$SUB" 'BEGIN{printf "%.4f\n", d/(s*1e6)}' >> "$TMP"
    e0=$e1; i=$((i+1))
done
sort -n "$TMP" | awk -v label="$LABEL" -v n="$n" -v win="$((n*SUB))" '
  {v[NR]=$1; sum+=$1}
  END{
    med=(NR%2)?v[(NR+1)/2]:(v[NR/2]+v[NR/2+1])/2;
    printf "[%s] package-0 over %ds (%d samples): mean=%.3f W  median=%.3f W  min=%.3f  max=%.3f\n",
           label, win, n, sum/NR, med, v[1], v[NR];
  }'
rm -f "$TMP"
