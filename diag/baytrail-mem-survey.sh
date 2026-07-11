#!/bin/sh
# baytrail-mem-survey.sh — memory inventory for the 2 GB Iconia W4-820. Read-only.
#   ssh -i /tmp/ik root@192.168.1.31 'sh -s' < baytrail-mem-survey.sh
set -u
sec(){ echo; echo "==================== $* ===================="; }

sec "1. FREE / SWAP (MB)"
free -m
echo "-- /proc/swaps --"; cat /proc/swaps

sec "2. ZRAM (compressed swap — the main 2GB lever)"
for z in /sys/block/zram*; do
    [ -e "$z/disksize" ] || continue
    echo "-- ${z##*/} --"
    ds=$(cat "$z/disksize"); echo "  disksize      = $((ds/1024/1024)) MB"
    for f in comp_algorithm mem_limit; do
        [ -e "$z/$f" ] && echo "  $f = $(cat "$z/$f")"
    done
    if [ -e "$z/mm_stat" ]; then
        # orig_data compr_data mem_used ... (bytes)
        set -- $(cat "$z/mm_stat")
        echo "  orig_data     = $(( ${1:-0}/1024/1024 )) MB"
        echo "  compr_data    = $(( ${2:-0}/1024/1024 )) MB"
        echo "  mem_used      = $(( ${3:-0}/1024/1024 )) MB"
        [ "${2:-0}" -gt 0 ] && awk -v o="${1:-0}" -v c="${2:-1}" 'BEGIN{printf "  ratio         = %.2fx\n", o/c}'
    fi
done

sec "3. VM TUNABLES"
for k in swappiness vfs_cache_pressure min_free_kbytes watermark_scale_factor \
         dirty_ratio dirty_background_ratio page-cluster; do
    echo "  vm.$k = $(cat /proc/sys/vm/$k 2>/dev/null)"
done

sec "4. TOP PROCESSES BY RSS (KB) — RSS overcounts shared mem, use for ranking"
ps -e -o rss= -o pid= -o comm= 2>/dev/null | sort -rn | head -25

sec "5. CHROME vs ARC vs VM footprint (summed RSS, MB)"
for pat in chrome arc android crosvm vm_concierge termina cras; do
    kb=$(ps -e -o rss=,comm= 2>/dev/null | awk -v p="$pat" 'tolower($2)~p{s+=$1} END{print s+0}')
    n=$(ps -e -o comm= 2>/dev/null | grep -ic "$pat")
    printf "  %-14s %5d MB  (%d procs)\n" "$pat" "$((kb/1024))" "$n"
done
echo "-- is ARC/Android actually up? --"
ps -e -o pid,comm 2>/dev/null | grep -iE 'arcvm|crosvm|android|arc_' | head
initctl status arcvm-* 2>/dev/null; initctl list 2>/dev/null | grep -iE 'arc|android|arcvm' | head

sec "6. TMPFS MOUNTS (RAM-backed — size vs used)"
df -h 2>/dev/null | awk 'NR==1 || /tmpfs/'

sec "7. MEMINFO highlights"
grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Shmem|Slab|SReclaimable|SUnreclaim|AnonPages|KernelStack|PageTables):' /proc/meminfo

sec "8. MEM daemons"
for s in resourced swap_management vm_concierge; do echo "  $s: $(initctl status $s 2>/dev/null)"; done
echo; echo "DONE — paste back to build the trim list."
