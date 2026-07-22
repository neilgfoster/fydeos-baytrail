#!/usr/bin/env bash
# build-rescue-image.sh - build the ThinkPad 10 20C1 RESCUE image: a minimal
# self-contained kernel+initramfs EFI executable (channel #2, see PROGRESS.md T4 and
# /home/neil/.claude/plans/zesty-waddling-fern.md). Boots the same already-proven-safe
# way shellx64.efi was booted in T3 - a one-time firmware boot entry, no bootloader
# needed since CONFIG_EFI_STUB + a built-in initramfs makes the bzImage itself a valid
# PE/EFI executable.
#
# This is a *separate*, much leaner build than scripts/build-kernel-standalone.sh's main
# OS kernel: same openFyde kernel git source (proven Bay Trail driver code), but config
# starts from upstream `x86_64_defconfig` instead of the full ChromeOS flavour, and there
# is no ChromeOS rootfs at all - just busybox + dropbear + wpasupplicant from Debian
# packages, assembled into an initramfs tree.
#
# Prereqs (Debian/Ubuntu): build-essential bc bison flex libssl-dev libelf-dev cpio kmod
#   rsync busybox-static dropbear-bin wpasupplicant e2fsprogs
#
# Usage:
#   scripts/build-rescue-image.sh --board <id> [clone|config|initramfs|build|all]
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
BOARD_ID="" ; ACTION="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --board) BOARD_ID=$2; shift 2 ;;
    clone|config|initramfs|build|all) ACTION=$1; shift ;;
    *) echo "usage: $0 --board <id> [clone|config|initramfs|build|all]"; exit 2 ;;
  esac
done
[ -n "$BOARD_ID" ] || { echo "ERROR: --board <id> required"; exit 2; }
BD="$HERE/boards/$BOARD_ID"
RD="$BD/rescue"
# shellcheck disable=SC1091
. "$BD/board.env"
[ "${CPU_64BIT:-yes}" = yes ] || { echo "ERROR: $BOARD_ID CPU is 32-bit; unsupported"; exit 1; }

# Separate clone from the main-OS kernel build (build-kernel-standalone.sh) - different
# .config needs (upstream defconfig base here, not the ChromeOS flavour), so they must
# not share a working tree.
SRC=${RESCUE_KERNEL_SRC:-$HOME/openfyde/kernel-6.6-rescue-$BOARD_ID}
IMROOT="$RD/initramfs"
JOBS=$(nproc)

deps(){
  for t in make gcc bc bison flex cpio busybox rsync; do
    command -v "$t" >/dev/null || { echo "MISSING toolchain: $t (apt install build-essential bc bison flex libssl-dev libelf-dev cpio kmod rsync)"; exit 1; }
  done
  for pkg_bin in /bin/busybox:busybox-static /usr/sbin/dropbear:dropbear-bin /sbin/wpa_supplicant:wpasupplicant /usr/sbin/sgdisk:gdisk /sbin/mke2fs:e2fsprogs /sbin/resize2fs:e2fsprogs /sbin/e2fsck:e2fsprogs; do
    p=${pkg_bin%%:*}; pkg=${pkg_bin##*:}
    [ -e "$p" ] || { echo "MISSING $p - apt install $pkg (and enable non-free-firmware for firmware-brcm80211)"; exit 1; }
  done
}

cmd_clone(){
  [ -d "$SRC/.git" ] && { echo "already cloned at $SRC"; return; }
  git clone --depth 1 --single-branch -b "$KERNEL_BRANCH" "$KERNEL_GIT" "$SRC"
  ( cd "$SRC" && make kernelversion )
}

cmd_config(){
  cd "$SRC"
  make x86_64_defconfig
  { echo "# --- $BOARD_ID rescue-minimal.config ---"; cat "$RD/config/rescue-minimal.config"; } >> .config
  # CONFIG_INITRAMFS_SOURCE is a build-path, not a static fragment value - inject it here.
  # Two space-separated sources: the assembled directory tree, plus a cpio-list text
  # file declaring /dev/console directly (see extra-nodes.list - real mknod isn't usable
  # in this build sandbox, CAP_MKNOD is unavailable even under sudo).
  echo "CONFIG_INITRAMFS_SOURCE=\"$IMROOT $RD/extra-nodes.list\"" >> .config
  make olddefconfig
  echo "=== rescue load-bearing config ==="
  grep -E 'CONFIG_(BRCMFMAC|CFG80211|MMC_SDHCI_ACPI|EFI_STUB|BLK_DEV_INITRD|INITRAMFS_SOURCE|DEVTMPFS_MOUNT|FB_EFI|USB_HID)=' .config \
    || { echo "WARNING: one or more load-bearing options missing from .config"; exit 1; }
}

# Copy a dynamically-linked binary plus every shared library `ldd` reports (including
# the dynamic linker itself, e.g. /lib64/ld-linux-x86-64.so.2, which ldd lists as $1
# rather than $3 since it has no "=>"), preserving each lib's absolute path under
# $IMROOT so the dynamic linker finds them unmodified.
copy_with_libs(){
  local bin=$1 destdir=$2
  install -Dm755 "$bin" "$IMROOT/$destdir/$(basename "$bin")"
  ldd "$bin" 2>/dev/null | awk '{print $3 ? $3 : $1}' | grep '^/' | while read -r lib; do
    [ -e "$IMROOT$lib" ] || install -Dm755 "$lib" "$IMROOT$lib"
  done
}

cmd_initramfs(){
  deps
  rm -rf "$IMROOT"
  mkdir -p "$IMROOT"/{bin,sbin,etc,proc,sys,dev,tmp,root,lib,lib64,lib/firmware/brcm,mnt/esp}

  # /dev/console device node: see $RD/extra-nodes.list (a kernel cpio-list source,
  # merged into CONFIG_INITRAMFS_SOURCE alongside this directory in cmd_config - real
  # `mknod` isn't usable here, this sandbox lacks CAP_MKNOD even under sudo). Found
  # necessary after the 4th real-hardware boot test: dmesg showed "Warning: unable to
  # open an initial console." - the kernel's own console_on_rootfs() couldn't find
  # /dev/console before exec'ing /init (this initramfs otherwise relies entirely on
  # CONFIG_DEVTMPFS_MOUNT to populate /dev, which apparently didn't win the race here),
  # so /init's fd 0/1/2 were plausibly never connected to anything - explaining "kernel
  # boot log is visible (printk doesn't go through a process's fds) but no shell prompts
  # and no response to typed input (read on a dead fd 0 returns immediately)".

  # busybox-static: single fully-static binary, symlink every applet name to it.
  install -Dm755 /bin/busybox "$IMROOT/bin/busybox"
  ( cd "$IMROOT" && ./bin/busybox --list ) | while read -r applet; do
    [ -e "$IMROOT/bin/$applet" ] || ln -s busybox "$IMROOT/bin/$applet"
  done

  # dropbear + wpa_supplicant: dynamically linked - bundle their resolved libs.
  copy_with_libs /usr/sbin/dropbear   sbin
  copy_with_libs /usr/bin/dropbearkey sbin
  copy_with_libs /sbin/wpa_supplicant sbin
  copy_with_libs /sbin/wpa_cli        sbin

  # sgdisk: dynamically linked GPT tool - needed to hand-place the ChromeOS partition
  # set into the eMMC's free gap from inside this rescue environment (see
  # boards/thinkpad10-20c1/PARTITION-DESIGN.md). Chosen over cgpt for the write path:
  # definitely apt-installable (gdisk package) and takes raw ChromeOS type GUIDs
  # directly, so its output is fully cgpt/vboot-compatible without needing cgpt itself.
  copy_with_libs /usr/sbin/sgdisk sbin

  # e2fsprogs (mke2fs/resize2fs/e2fsck): needed to create a real ext4 filesystem on
  # STATE and grow the dd'd ROOT-A rootfs to fill its partition (see
  # boards/thinkpad10-20c1/PARTITION-DESIGN.md's filesystem-creation step, T9). BusyBox's
  # own built-in `mke2fs` applet (already symlinked into bin/ by the applet loop above)
  # is ext2-only with no `-t`/journal/extents support, and BusyBox has no `resize2fs`
  # applet at all - found live, on real hardware, when T9's plan first tried to run
  # `mkfs.ext4` (not found) against this image. Real e2fsprogs picks its target fs type
  # from argv[0] (`mkfs.ext4` vs `mke2fs`), so symlink the conventional names alongside
  # the one real binary - same shape as the busybox applet-symlink loop above. Installed
  # into sbin/, which PATH resolves before bin/ (where busybox's mke2fs symlink lives),
  # so the real binary wins.
  copy_with_libs /sbin/mke2fs   sbin
  copy_with_libs /sbin/resize2fs sbin
  copy_with_libs /sbin/e2fsck   sbin
  for alias in mkfs.ext2 mkfs.ext3 mkfs.ext4; do
    ln -sf mke2fs "$IMROOT/sbin/$alias"
  done

  # WiFi firmware: from Debian's firmware-brcm80211 (non-free-firmware component -
  # `apt-get install firmware-brcm80211`). This device's actual chip identifies itself
  # as needing revision **b5**, not b4 (confirmed via a real-hardware boot-test dmesg:
  # "brcmf_fw_alloc_request: using brcm/brcmfmac43241b5-sdio for chip BCM4324/6" - W4-820
  # uses a different chip revision, b4, which is why the initial guess copied the wrong
  # one). Ship both b4 and b5 rather than re-guess. No NVRAM/SROM .txt is bundled: neither
  # Debian's package nor this device's own Windows Broadcom driver (oem24.inf references
  # bcm943241ipaagb_p100*.txt, but no such file actually exists in
  # C:\Windows\system32\drivers - checked directly over SSH) ships one for this chip
  # revision, so calibration is apparently embedded in the dongle firmware image itself.
  for rev in b4 b5; do
    FW="/lib/firmware/brcm/brcmfmac43241${rev}-sdio.bin"
    [ -f "$FW" ] || { echo "MISSING $FW - apt install firmware-brcm80211 (enable non-free-firmware component first)"; exit 1; }
    install -Dm644 "$FW" "$IMROOT/lib/firmware/brcm/brcmfmac43241${rev}-sdio.bin"
  done

  # skel/ overlay: init script + /etc templates (tracked in git, see rescue/skel/).
  rsync -a "$RD/skel/" "$IMROOT/"
  chmod 755 "$IMROOT/init"

  # Fixed dropbear host key: generate once, persist OUTSIDE git (a leaked host key only
  # enables MITM impersonation, not login - auth is password-gated separately - but
  # there's no reason to commit key material). Reused across rebuilds so known_hosts
  # doesn't churn.
  HOSTKEY_DIR="$RD/hostkey"; mkdir -p "$HOSTKEY_DIR"
  if [ ! -f "$HOSTKEY_DIR/dropbear_ed25519_host_key" ]; then
    dropbearkey -t ed25519 -f "$HOSTKEY_DIR/dropbear_ed25519_host_key"
  fi
  install -Dm600 "$HOSTKEY_DIR/dropbear_ed25519_host_key" \
    "$IMROOT/etc/dropbear/dropbear_ed25519_host_key"

  echo "initramfs tree assembled at $IMROOT"
}

cmd_build(){
  deps; cd "$SRC"
  # Force the built-in initramfs to regenerate. The kernel's cpio dependency tracking
  # does NOT reliably detect in-place content changes to files under the initramfs tree
  # - T14 hit this: an initramfs-only edit (skel/init) rebuilt to a byte-identical image
  # with a stale cpio, silently shipping the old init. Dropping the cached archive before
  # every build guarantees the current initramfs tree is embedded.
  rm -f usr/initramfs_data.cpio
  make -j"$JOBS" bzImage
  mkdir -p "$RD/out"; cp -f arch/x86/boot/bzImage "$RD/out/rescuex64.efi"
  # `file`(1) classifies an EFI-stub bzImage as "Linux kernel x86 boot executable"
  # rather than "PE32+" even though it's a valid dual-format file (that IS the point
  # of CONFIG_EFI_STUB - firmware loads it directly as a PE image) - so check the PE
  # header for real: the x86 boot protocol's `pe_header` field at offset 0x3c is a
  # little-endian offset that must point to a "PE\0\0" signature.
  local f="$RD/out/rescuex64.efi"
  local pe_off; pe_off=$(od -An -tu4 -j 60 -N 4 --endian=little "$f" 2>/dev/null | tr -d ' ')
  local sig; sig=$(dd if="$f" bs=1 skip="$pe_off" count=4 2>/dev/null)
  [ "$sig" = "PE" ] \
    && echo "built -> boards/$BOARD_ID/rescue/out/rescuex64.efi (valid PE/EFI, pe_header @ $pe_off)" \
    || { echo "WARNING: no PE\\0\\0 signature at pe_header offset $pe_off - not a valid EFI executable"; exit 1; }
}

case "$ACTION" in
  clone) cmd_clone ;;
  config) cmd_config ;;
  initramfs) cmd_initramfs ;;
  build) cmd_build ;;
  all) cmd_clone; cmd_config; cmd_initramfs; cmd_build ;;
esac
