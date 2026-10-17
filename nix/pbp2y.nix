# 007-pbp2y: pbp2n + a much faster start (power-on -> kernel 15.3 s -> 5.3 s on my Pinebook Pro)
# and no countdown. Everything in it:
#  - pbp1: backlight off at kernel handoff, dimmer Tow-Boot screen, FDTOVERLAYS,
#    1 s countdown (patch 0001); pbp2y has no countdown (BOOTDELAY 0, see the end)
#  - btrfs, with fixes backported from U-Boot master (patches 0002-0007, 0010)
#  - U-Boot's start-up stack at 0x03f00000 instead of 0x300000 (CUSTOM_SYS_INIT_SP_ADDR),
#    as upstream U-Boot does now; with btrfs the image no longer fits below 0x300000
#  - only the internal keyboard's USB controllers at power-on ($usb_only, patch 0008)
#  - SD card at 50 MHz instead of 20 MHz (patch 0009)
#  - the touchpad no longer freezes the keyboard in the menu (patch 0011, Tow-Boot#57)
#  - upstream XHCI robustness fixes (patches 0012-0021): no reset on XHCI event timeouts
#  - keyboard fallback (patch 0022): no keyboard after the power-on USB start -> start all controllers
#  - several USB keyboards at once (patch 0023): an external keyboard works next to the internal one
#  - eMMC in HS200 at up to 200 MHz instead of 25 MHz (patch 0024). HS400 Enhanced Strobe was
#    tried (2026-10-15) and broke the hand-over to Linux, so it's not in here
#  - TF-A: big-core and GPU regulators off in suspend (tfa-0001): drives their VSEL pins
#    GPIO1_C1/GPIO1_B6 high in sleep, as Rockchip's own BL31 does
#  - SPI flash read at 25 MHz (24.75 real) instead of 10 MHz (patch 0026 + SF_DEFAULT_SPEED):
#    SPL reads the 1.2 MB U-Boot FIT from it on every boot. 33 MHz read fine, 49.5 MHz didn't
#  - boot timing handed to the kernel in /proc/device-tree/bootstage (scripts/bootstage.sh)
#  - kernel loaded at 0x02200000 instead of 0x02080000 (patch 0027), so booti no longer moves
#    a 49 MB Image to the next 2 MB boundary before starting it
#  - boot timing also from TPL and SPL (stashed at 0x03000000 and handed on), every U-Boot
#    init function and device probe that takes 5 ms or more (patch 0028), and marks between
#    main_loop and the kernel (patch 0030); u-boot.map + System.map are kept in debug/ to
#    look the addresses up. Pre-relocation malloc 16 -> 32 KB for the larger timing table
#  - the frame buffer is cleared after relocation with the cache on (patch 0029): Tow-Boot
#    cleared it before relocation with the cache off, 0.86 s per boot
#  - malloc area not cleared at start (SYS_MALLOC_CLEAR_ON_INIT off, 42 ms)
#  - device probes split into pinctrl / assigned clocks / the rest / driver probe, and each
#    assigned clock rate timed (patch 0031)
#  - instruction cache on as the first init function (patch 0032): before relocation U-Boot
#    ran with both caches off, 1.1 s for board_init_f
#  - CRU assigned-clocks removed from U-Boot proper's DT (patch 0033): all no-ops there, but
#    looking them up took 2 x 0.34 s (quadratic phandle walk)
#  - instruction cache on in SPL too (patch 0034), off again before TF-A: end of TPL -> U-Boot
#    took 3.9 s, mostly SPL's SPI read loop running without it
#  - SPL writes four timestamps to 0x03001000 that U-Boot turns into records (patch 0035, debug
#    only), and the kernel's device tree keeps 8 KB free for the bootstage node (patch 0036)
#  - data cache on in SPL after spl_early_init (patch 0037, page tables at 0x03100000): SPL's
#    SPI read of U-Boot + TF-A took 1.5 s for 1.2 MB with only the instruction cache
#  - data cache on in U-Boot proper before relocation too (patch 0038): temporary page tables
#    at 0x03100000, flushed and switched off before relocation; board_init_f took 0.62 s.
#    The first version (unreleased pbp2w/pbp2x) didn't boot from the chip: it cleared the
#    page-table fill pointer only in the old gd, after setup_reloc() had copied it
#  - no countdown (BOOTDELAY 0): Tow-Boot still checks for a key once, so hold ESC at power-on
#    to get the menu
# The version is set with releaseIdentifier, so every variant and the SBOM say 007-pbp2y.
#
# Build from a Tow-Boot checkout (tag release-2023.07-007):
#   nix-build -A pine64-pinebookPro --arg configuration /path/to/nix/pbp2y.nix
{ lib, pkgs, ... }:
{
  Tow-Boot.releaseIdentifier = lib.mkForce "-pbp2y";
  Tow-Boot.patches = [
    ../patches/0001-pbp-backlight.patch
    ../patches/0002-btrfs-fix-some-error-checking-for-btrfs_decompress.patch
    ../patches/0003-fs-btrfs-fix-reading-when-length-specified.patch
    ../patches/0004-fs-btrfs-fix-out-of-bounds-write.patch
    ../patches/0005-fs-btrfs-Do-not-free-multi-when-guaranteed-to-be-NUL.patch
    ../patches/0006-fs-btrfs-release-the-path-when-btrfs_search_slot-fai.patch
    ../patches/0007-fs-btrfs-fix-zstd-decompression-of-compressed-inline.patch
    ../patches/0008-usb-only.patch
    ../patches/0009-pbp-sd-50mhz.patch
    ../patches/0010-btrfs-list-subvolumes.patch
    ../patches/0011-usb-kbd-drain.patch
    ../patches/0012-usb-xhci-Fix-double-free-on-failure.patch
    ../patches/0013-usb-xhci-Guard-all-calls-to-xhci_wait_for_event.patch
    ../patches/0014-usb-xhci-Better-error-handling-in-abort_td.patch
    ../patches/0015-usb-xhci-Allow-context-state-errors-when-halting-an-.patch
    ../patches/0016-usb-xhci-Recover-from-halted-bulk-endpoints.patch
    ../patches/0017-usb-xhci-Fail-on-attempt-to-queue-TRBs-to-a-halted-e.patch
    ../patches/0018-usb-xhci-Do-not-panic-on-event-timeouts.patch
    ../patches/0019-usb-xhci-Fix-DMA-address-calculation-in-queue_trb.patch
    ../patches/0020-usb-xhci-Abort-transfers-with-unallocated-rings.patch
    ../patches/0021-usb-xhci-fix-DMA-address-corruption-in-abort_td.patch
    ../patches/0022-usb-start-all-controllers-if-a-partial-start-found-n.patch
    ../patches/0023-usb-kbd-multi-keyboard.patch
    ../patches/0024-pinebook-pro-let-U-Boot-run-the-eMMC-at-HS200-speed.patch
    ../patches/0026-pinebook-pro-read-the-SPI-flash-at-25-MHz-instead-of.patch
    ../patches/0027-rockchip-rk3399-load-the-kernel-at-a-2-MB-aligned-ad.patch
    ../patches/0028-bootstage-record-slow-init-functions-and-device-prob.patch
    ../patches/0029-video-clear-the-frame-buffer-after-relocation-with-t.patch
    ../patches/0030-bootstage-mark-the-steps-between-main_loop-and-the-k.patch
    ../patches/0031-bootstage-split-slow-device-probes-further.patch
    ../patches/0032-board_f-arm64-turn-the-instruction-cache-on-before-r.patch
    ../patches/0033-pinebook-pro-drop-the-CRU-assigned-clocks-from-U-Boo.patch
    ../patches/0034-rockchip-spl-turn-the-instruction-cache-on.patch
    ../patches/0035-DEBUG-spl-record-timestamps-outside-the-bootstage-st.patch
    ../patches/0036-image-fdt-leave-room-for-the-bootstage-node.patch
    ../patches/0037-rockchip-rk3399-spl-turn-the-data-cache-on.patch
    ../patches/0038-board_f-rk3399-turn-the-data-cache-on-before-relocat.patch
  ];
  Tow-Boot.builder.additionalArguments.BL31 = lib.mkForce "${
    pkgs.Tow-Boot.armTrustedFirmwareRK3399.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/tfa-0001-pbp-suspend-gpios.patch ];
    })
  }/bl31.elf";
  Tow-Boot.builder.installPhase = ''
    mkdir -p $out/debug
    cp u-boot u-boot.map System.map spl/u-boot-spl spl/u-boot-spl.map tpl/u-boot-tpl tpl/u-boot-tpl.map $out/debug/ || true
  '';
  Tow-Boot.config = [
    (helpers: with helpers; {
      BOOTDELAY = lib.mkForce (freeform "0");
      OF_LIBFDT_OVERLAY = yes;
      FS_BTRFS = yes;
      CMD_BTRFS = yes;
      SF_DEFAULT_SPEED = lib.mkForce (freeform "25000000");
      BOOTSTAGE = yes;
      BOOTSTAGE_FDT = yes;
      CMD_BOOTSTAGE = yes;
      BOOTSTAGE_RECORD_COUNT = lib.mkForce (freeform "80");
      SPL_BOOTSTAGE = yes;
      TPL_BOOTSTAGE = yes;
      SPL_BOOTSTAGE_RECORD_COUNT = freeform "16";
      TPL_BOOTSTAGE_RECORD_COUNT = freeform "8";
      BOOTSTAGE_STASH = yes;
      BOOTSTAGE_STASH_ADDR = lib.mkForce (freeform "0x03000000");
      SYS_MALLOC_F_LEN = lib.mkForce (freeform "0x8000");
      SPL_SYS_MALLOC_F_LEN = lib.mkForce (freeform "0x4000");
      TPL_SYS_MALLOC_F_LEN = lib.mkForce (freeform "0x4000");
      SYS_MALLOC_CLEAR_ON_INIT = lib.mkForce no;
      CUSTOM_SYS_INIT_SP_ADDR = lib.mkForce (freeform "0x03f00000");
      PREBOOT = lib.mkForce (freeform ''"setenv usb_only usb@fe380000 usb@fe3a0000; usb start; setenv usb_only"'');
    })
  ];
}
