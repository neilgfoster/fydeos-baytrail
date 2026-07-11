#!/bin/sh
# iconia-batlog.sh — lightweight detached battery-drain logger for the before/
# after "verify" of a power change. Samples every 3 min to a CSV on the stateful
# /var/log (survives ssh logout via setsid; survives reboot as a file, but the
# loop must be relaunched after a reboot).
#
# START (detached):  ssh -i /tmp/ik root@IP 'setsid sh /tmp/iconia-batlog.sh >/dev/null 2>&1 </dev/null & echo pid $!'
# READ:              (see iconia-batlog reader one-liner in the campaign notes)
# STOP:              ssh -i /tmp/ik root@IP 'pkill -f iconia-batlog.sh'
F=/var/log/iconia-batlog.csv
B=/sys/class/power_supply/BATC
BL=/sys/class/backlight/intel_backlight
ALS=/sys/bus/iio/devices/iio:device2/in_illuminance_raw
[ -f "$F" ] || echo "epoch,cap,charge_now_uAh,brightness,status,lux" > "$F"
while :; do
    printf '%s,%s,%s,%s,%s,%s\n' \
      "$(date +%s)" "$(cat $B/capacity 2>/dev/null)" "$(cat $B/charge_now 2>/dev/null)" \
      "$(cat $BL/actual_brightness 2>/dev/null)" "$(cat $B/status 2>/dev/null)" \
      "$(cat $ALS 2>/dev/null)" >> "$F"
    sleep 180
done
