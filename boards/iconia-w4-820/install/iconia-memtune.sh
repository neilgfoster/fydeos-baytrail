#!/bin/sh
# iconia-memtune.sh — memory tuning for the 2 GB Iconia W4-820. Runs at boot via
# iconia-memtune.conf, AFTER ChromeOS's swap setup, then converts zram to zstd and
# applies low-RAM vm knobs. Idempotent + safe (only reconfigures zram when it's
# empty, so no in-use swap is dropped).
#
# Rationale (see PROGRESS.md session 7): device is 2 GB; Chrome is the consumer
# (~25 renderers). zram is already 3.7 GB but ChromeOS builds it on lz4 — zstd holds
# ~30% more pages in the same RAM. swappiness up = prefer compressing anon over
# evicting page cache (zram is fast).
set -u
LOG="logger -t iconia-memtune"
Z=/sys/block/zram0

# --- zram -> zstd (only if present, empty, and not already zstd) ---
if [ -e "$Z/comp_algorithm" ]; then
    cur=$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$Z/comp_algorithm")
    used=$(awk '/zram0/{print $4}' /proc/swaps 2>/dev/null)
    if [ "$cur" != zstd ] && [ "${used:-0}" = 0 ]; then
        DS=$(cat "$Z/disksize")
        if swapoff /dev/zram0 2>/dev/null; then
            echo 1 > "$Z/reset" 2>/dev/null
            echo zstd > "$Z/comp_algorithm" 2>/dev/null
            echo "$DS" > "$Z/disksize" 2>/dev/null
            mkswap /dev/zram0 >/dev/null 2>&1
            swapon -p -2 /dev/zram0 2>/dev/null
            $LOG "zram -> zstd ($((DS/1024/1024))MB)"
        fi
    fi
fi

# --- vm knobs for a zram-backed low-RAM box ---
echo 100  > /proc/sys/vm/swappiness            2>/dev/null   # prefer zram over cache evict
echo 8192 > /proc/sys/vm/min_free_kbytes       2>/dev/null   # reclaim headroom (avoid stalls)
echo 0    > /proc/sys/vm/page-cluster          2>/dev/null   # 1 page/swapin (best for zram)
$LOG "vm knobs applied (swappiness=100 min_free=8192 page-cluster=0)"

exit 0
