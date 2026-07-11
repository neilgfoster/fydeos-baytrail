#!/bin/sh
# baytrail-pwr-sample.sh — A/B battery-draw sampler for the one-change-at-a-time
# power campaign. Run UNPLUGGED, screen in a FIXED state, hands off.
#
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < baytrail-pwr-sample.sh [WIN_S] [INT_S] [LABEL]
#   defaults: WIN=90s  INT=3s
#
# Reports mean/median/min/max of current_now (instantaneous gauge) AND the
# coulomb-counted average from the charge_now delta (ground truth). Compare the
# MEDIAN across runs — it rejects Chrome/wifi spikes better than the mean.
set -u
WIN=${1:-90}; INT=${2:-3}; LABEL=${3:-run}
B=/sys/class/power_supply/BATC
TMP=/tmp/.pwr_samples.$$
: > "$TMP"

st=$(cat "$B/status" 2>/dev/null)
[ "$st" = "Discharging" ] || echo "NOTE: status=$st — UNPLUG for a valid drain number."

full=$(cat "$B/charge_full")
c0=$(cat "$B/charge_now"); cap0=$(cat "$B/capacity"); t0=$(date +%s)
n=0
end=$(( t0 + WIN ))
while [ "$(date +%s)" -lt "$end" ]; do
    cat "$B/current_now" >> "$TMP"; n=$((n+1))
    sleep "$INT"
done
c1=$(cat "$B/charge_now"); cap1=$(cat "$B/capacity"); t1=$(date +%s)

sort -n "$TMP" > "$TMP.s"
awk -v full="$full" -v c0="$c0" -v c1="$c1" -v cap0="$cap0" -v cap1="$cap1" \
    -v dt="$((t1-t0))" -v label="$LABEL" -v n="$n" '
  { v[NR]=$1; sum+=$1 }
  END{
    mean=sum/NR; mn=v[1]; mx=v[NR];
    med=(NR%2)? v[(NR+1)/2] : (v[NR/2]+v[NR/2+1])/2;
    hrs=dt/3600.0; dC=c0-c1; coul=(dC/1000.0)/hrs;
    printf "===== [%s] n=%d dt=%ds =====\n", label, n, dt;
    printf "current_now mA : median=%.0f  mean=%.0f  min=%.0f  max=%.0f\n",
           med/1000, mean/1000, mn/1000, mx/1000;
    printf "coulomb  mA    : %.0f   (charge %d -> %d uAh)\n", coul, c0, c1;
    printf "capacity       : %d%% -> %d%%\n", cap0, cap1;
    if (coul>0) printf "est runtime    : %.1f h from full (%.2f Ah)\n", (full/1000.0)/coul, full/1e6;
    printf ">>> compare the MEDIAN mA across changes <<<\n";
  }' "$TMP.s"
rm -f "$TMP" "$TMP.s"
