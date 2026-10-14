# 007-pbp2i: the current build.
#  - pbp1: backlight off at kernel handoff, dimmer Tow-Boot screen, FDTOVERLAYS,
#    1 s countdown (patch 0001)
#  - btrfs, with fixes backported from U-Boot master (patches 0002-0007, 0010)
#  - U-Boot's start-up stack at 0x03f00000 instead of 0x300000 (CUSTOM_SYS_INIT_SP_ADDR),
#    as upstream U-Boot does now; with btrfs the image no longer fits below 0x300000
#  - only the internal keyboard's USB controllers at power-on ($usb_only, patch 0008)
#  - SD card at 50 MHz instead of 20 MHz (patch 0009)
#  - the touchpad no longer freezes the keyboard in the menu (patch 0011, Tow-Boot#57)
# The version is set with releaseIdentifier, so every variant and the SBOM say 007-pbp2i.
#
# Build from a Tow-Boot checkout (tag release-2023.07-007):
#   nix-build -A pine64-pinebookPro --arg configuration /path/to/nix/pbp2i.nix
{ lib, ... }:
{
  Tow-Boot.releaseIdentifier = lib.mkForce "-pbp2i";
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
  ];
  Tow-Boot.config = [
    (helpers: with helpers; {
      BOOTDELAY = lib.mkForce (freeform "1");
      OF_LIBFDT_OVERLAY = yes;
      FS_BTRFS = yes;
      CMD_BTRFS = yes;
      CUSTOM_SYS_INIT_SP_ADDR = lib.mkForce (freeform "0x03f00000");
      PREBOOT = lib.mkForce (freeform ''"setenv usb_only usb@fe380000 usb@fe3a0000; usb start; setenv usb_only"'');
    })
  ];
}
