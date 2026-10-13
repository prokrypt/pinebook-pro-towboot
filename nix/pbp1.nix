# 007-pbp1: backlight off at kernel handoff, dimmer Tow-Boot screen,
# FDTOVERLAYS support, 1 s countdown.
# Build from a Tow-Boot checkout (tag release-2023.07-007):
#   nix-build -A pine64-pinebookPro --arg configuration /path/to/nix/pbp1.nix
{ lib, ... }:
{
  Tow-Boot.patches = [ ../patches/0001-pbp-backlight.patch ];
  Tow-Boot.config = [
    (helpers: with helpers; {
      BOOTDELAY = lib.mkForce (freeform "1");
      OF_LIBFDT_OVERLAY = yes;
      IDENT_STRING = lib.mkForce (freeform ''" 007-pbp1 [variant: spi]"'');
    })
  ];
}
