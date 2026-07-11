#!/bin/sh
# iconia-pwr-survey.sh — one-shot inventory to build the power hit-list:
# what's loaded, what's running, how deep the CPU idles, what keeps it awake.
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < iconia-pwr-survey.sh
set -u
sec(){ echo; echo "==================== $* ===================="; }

sec "1. LOADED MODULES (by size — unload candidates for dead/unused HW)"
lsmod | sort -k2 -nr | awk 'NR==1{print;next}{printf "%-24s %8s  used_by=%s\n",$1,$2,$4}' | head -60

sec "2. RUNNING UPSTART JOBS (service trim candidates)"
initctl list 2>/dev/null | grep -w running | sort

sec "3. TOP PROCESSES BY CPU (redundant/busy daemons)"
{ ps -e -o pcpu= -o pid= -o comm= 2>/dev/null || ps -eo pcpu,pid,comm 2>/dev/null; } \
  | sort -rn | head -25

sec "4. CPU IDLE — C-state residency (want most time in the DEEPEST state)"
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
    [ -d "$s" ] || continue
    printf "  %-8s %-10s usage=%-10s time_us=%-12s disable=%s\n" \
      "${s##*/}" "$(cat "$s/name")" "$(cat "$s/usage")" "$(cat "$s/time")" "$(cat "$s/disable" 2>/dev/null)"
done
echo "  max_cstate=$(cat /sys/module/intel_idle/parameters/max_cstate 2>/dev/null)"
echo "  governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) cur=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)kHz"

sec "5. WAKEUP SOURCES (what interrupts idle) — top by count"
mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
if [ -r /sys/kernel/debug/wakeup_sources ]; then
    awk 'NR==1{next} {print $6, $1}' /sys/kernel/debug/wakeup_sources | sort -rn | head -12
else echo "  (wakeup_sources unavailable)"; fi

sec "6. INTERRUPT ACTIVITY (busiest IRQs — a proxy for wakeups)"
awk 'NR>1{s=0; for(i=2;i<=NF-2;i++) s+=$i; if(s>0) print s, $1, $NF}' /proc/interrupts \
  | sort -rn | head -12

sec "7. BACKLIGHT / DISPLAY"
echo "  brightness=$(cat /sys/class/backlight/intel_backlight/brightness 2>/dev/null)/$(cat /sys/class/backlight/intel_backlight/max_brightness 2>/dev/null)"

sec "8. BATTERY (measurement source)"
echo "  status=$(cat /sys/class/power_supply/BATC/status) cap=$(cat /sys/class/power_supply/BATC/capacity)% current_now=$(cat /sys/class/power_supply/BATC/current_now)uA charge_full=$(cat /sys/class/power_supply/BATC/charge_full)uAh"
echo; echo "DONE — paste this back to build the change list."
