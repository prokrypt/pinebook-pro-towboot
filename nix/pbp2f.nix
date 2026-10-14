# 007-pbp2f: everything in pbp2c (btrfs, stack fix), plus a faster USB start:
# at boot only the internal keyboard's USB controllers are started ($usb_only,
# patch 0008); "Rescan USB", "Boot from USB" and USB network boot still start
# all of them. Saves ~5.7 s per boot on the Pinebook Pro.
#
# btrfs: fixes backported from U-Boot master (patches 0002-0007).
#
# CUSTOM_SYS_INIT_SP_ADDR moves U-Boot proper's start-up stack from 0x300000
# to 0x03f00000 (the value current upstream U-Boot uses on Rockchip). With
# btrfs, U-Boot + its device tree (loaded at 0x200000) no longer fit below
# the early stack/heap at 0x300000, which is why 007-pbp2 didn't start.
#
# Build from a Tow-Boot checkout (tag release-2023.07-007):
#   nix-build -A pine64-pinebookPro --arg configuration /path/to/nix/pbp2f.nix
{ lib, ... }:
{
  Tow-Boot.patches = [
    ../patches/0001-pbp-backlight.patch
    ../patches/0002-btrfs-fix-some-error-checking-for-btrfs_decompress.patch
    ../patches/0003-fs-btrfs-fix-reading-when-length-specified.patch
    ../patches/0004-fs-btrfs-fix-out-of-bounds-write.patch
    ../patches/0005-fs-btrfs-Do-not-free-multi-when-guaranteed-to-be-NUL.patch
    ../patches/0006-fs-btrfs-release-the-path-when-btrfs_search_slot-fai.patch
    ../patches/0007-fs-btrfs-fix-zstd-decompression-of-compressed-inline.patch
    ../patches/0008-usb-only.patch
  ];
  Tow-Boot.config = [
    (helpers: with helpers; {
      BOOTDELAY = lib.mkForce (freeform "1");
      OF_LIBFDT_OVERLAY = yes;
      FS_BTRFS = yes;
      CMD_BTRFS = yes;
      CUSTOM_SYS_INIT_SP_ADDR = lib.mkForce (freeform "0x03f00000");
      PREBOOT = lib.mkForce (freeform ''"setenv usb_only usb@fe380000 usb@fe3a0000; usb start; setenv usb_only"'');
      IDENT_STRING = lib.mkForce (freeform ''" 007-pbp2f [variant: spi]"'');
    })
  ];
}
