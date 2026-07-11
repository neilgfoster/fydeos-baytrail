#!/bin/sh
# baytrail-power-diag.sh — READ-ONLY power/battery/charging survey of the LIVE eMMC
# system. Answers three questions in one pass:
#   1. Why is the ChromeOS charging bolt missing? (AXP288 charger + extcon state)
#   2. Where is the power going? (cpufreq governor, backlight, wakeups, S0ix)
#   3. What UX-safe knobs exist to make it sip power?
#
# Run from the crosh host:  ssh -i /tmp/ik root@192.168.1.31 'sh -s' < baytrail-power-diag.sh
# Nothing here writes; safe to run anytime (does NOT stop powerd).
set -u

sec() { echo; echo "==================== $* ===================="; }
dump() { for f in "$@"; do [ -e "$f" ] && printf '%-46s = %s\n' "$f" "$(cat "$f" 2>/dev/null)"; done; }

sec "1. POWER SUPPLIES (the charging-icon question)"
# ChromeOS draws the bolt when powerd sees a line-power supply with online=1.
# Fuel gauge (battery %) working but no bolt => the *charger* supply is the problem.
for ps in /sys/class/power_supply/*; do
    [ -e "$ps" ] || continue
    echo "--- ${ps##*/} ---"
    dump "$ps/type" "$ps/online" "$ps/present" "$ps/status" \
         "$ps/capacity" "$ps/capacity_level" "$ps/health" \
         "$ps/voltage_now" "$ps/current_now" "$ps/input_current_limit" \
         "$ps/constant_charge_current" "$ps/constant_charge_current_max" \
         "$ps/model_name" "$ps/manufacturer" "$ps/scope"
done

sec "2. EXTCON (USB cable-type detection — feeds the charger 'online')"
# AXP288 charger only flips online=1 when axp288_extcon reports a cable (SDP/CDP/DCP).
# If extcon says nothing is connected, the bolt never shows even while charging.
for ec in /sys/class/extcon/*; do
    [ -e "$ec" ] || continue
    echo "--- ${ec##*/} ($(cat "$ec/name" 2>/dev/null)) ---"
    for state in "$ec"/cable.*/state "$ec"/state; do
        [ -e "$state" ] && printf '%-46s = %s\n' "$state" "$(cat "$state" 2>/dev/null)"
    done
done
echo "-- axp288 / extcon / charger in dmesg --"
dmesg 2>/dev/null | grep -iE 'axp288|extcon|charger|fuel|tcpc|bq2|vbus' | tail -30

sec "3. POWERD — what the ChromeOS power manager sees"
echo "-- powerd running? --"; initctl status powerd 2>/dev/null || status powerd 2>/dev/null
echo "-- default prefs of interest --"
for p in /usr/share/power_manager/*; do
    case "${p##*/}" in
      *charge*|*battery*|*suspend*|*idle*|*dim*|*backlight*|*ac_*|*plugged*) \
        printf '%-46s = %s\n' "${p##*/}" "$(cat "$p" 2>/dev/null)";;
    esac
done
echo "-- board/stateful overrides (these win) --"
ls -la /var/lib/power_manager/ 2>/dev/null
for p in /var/lib/power_manager/*; do
    [ -f "$p" ] && printf '%-46s = %s\n' "${p##*/}" "$(cat "$p" 2>/dev/null)"
done
echo "-- powerd tail (charger/suspend decisions) --"
tail -40 /var/log/power_manager/powerd.LATEST 2>/dev/null | \
    grep -iE 'charge|ac |usb |line|online|suspend|dark|backlight|battery' | tail -25

sec "4. CPU — governor & frequency (biggest active-draw lever)"
dump /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver \
     /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor \
     /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors \
     /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq \
     /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq \
     /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq \
     /sys/devices/system/cpu/intel_pstate/no_turbo \
     /sys/module/intel_idle/parameters/max_cstate
echo "-- per-cpu governor --"
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    printf '%s = %s\n' "$g" "$(cat "$g" 2>/dev/null)"
done

sec "5. BACKLIGHT (known full-bright => a real drain; UX vs power)"
ls /sys/class/backlight/ 2>/dev/null || echo "(no /sys/class/backlight entries — expected, DSI PWM unbound)"
dump /sys/class/backlight/*/brightness /sys/class/backlight/*/max_brightness \
     /sys/class/backlight/*/actual_brightness

sec "6. SUSPEND / S0ix residency (idle-draw ceiling)"
dump /sys/power/mem_sleep /sys/power/state
echo "-- suspend stats --"; cat /sys/kernel/debug/suspend_stats 2>/dev/null | head -20
echo "-- s0ix / pmc residency (Bay Trail telemetry, if exposed) --"
for f in /sys/kernel/debug/pmc_core/*residency* /sys/kernel/debug/telemetry/*; do
    [ -e "$f" ] && printf '%s = %s\n' "$f" "$(cat "$f" 2>/dev/null | head -1)"
done

sec "7. WAKEUP SOURCES & IRQ noise (what keeps it awake)"
echo "-- enabled wakeup devices --"
for w in /sys/devices/**/power/wakeup; do :; done 2>/dev/null
grep -rl enabled /sys/devices/*/power/wakeup 2>/dev/null | head -40 | while read -r f; do
    echo "  ${f%/wakeup}"
done
echo "-- top wakeup_sources by active_count --"
awk 'NR==1||$6+0>0{print}' /sys/kernel/debug/wakeup_sources 2>/dev/null | sort -k6 -nr | head -15
echo "-- busiest interrupts --"
sort -k2 -nr /proc/interrupts 2>/dev/null | head -12

sec "8. RUNTIME PM & powertop (if present)"
command -v powertop >/dev/null 2>&1 && echo "powertop: available" || echo "powertop: NOT installed"
echo "-- devices NOT using runtime PM autosuspend --"
grep -L auto /sys/devices/*/power/control 2>/dev/null | head; :
for c in /sys/bus/{i2c,usb,platform,sdio,pci}/devices/*/power/control; do
    [ -e "$c" ] || continue
    v=$(cat "$c" 2>/dev/null); [ "$v" = "auto" ] || echo "  on: ${c%/power/control}"
done | head -30

sec "DONE"
echo "Paste this whole output back. Key reads:"
echo "  #1/#2 -> charger 'online' & extcon cable => charging-icon fix"
echo "  #4    -> governor (want a UX-safe on-demand/schedutil, not 'performance')"
echo "  #6/#7 -> whether idle-draw is even improvable on this firmware"
