# 007-pbp2: everything in pbp1, plus
# BROKEN: this build does not start (image too big for the 0x300000 early stack in U-Boot 2023.07). Kept for reference; see README.
#  - btrfs support (/boot can live on btrfs), with fixes backported from
#    U-Boot master (patches 0002-0007)
#  - boot timing handed to the kernel in /proc/device-tree/bootstage
# Build from a Tow-Boot checkout (tag release-2023.07-007):
#   nix-build -A pine64-pinebookPro --arg configuration /path/to/nix/pbp2.nix
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
  ];
  Tow-Boot.config = [
    (helpers: with helpers; {
      BOOTDELAY = lib.mkForce (freeform "1");
      OF_LIBFDT_OVERLAY = yes;
      FS_BTRFS = yes;
      CMD_BTRFS = yes;
      BOOTSTAGE = yes;
      BOOTSTAGE_FDT = yes;
      CMD_BOOTSTAGE = yes;
      IDENT_STRING = lib.mkForce (freeform ''" 007-pbp2 [variant: spi]"'');
    })
  ];
}
