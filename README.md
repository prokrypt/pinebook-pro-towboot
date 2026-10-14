# Tow-Boot for the Pinebook Pro, with fixes

A small set of patches on top of [Tow-Boot](https://tow-boot.org) `2023.07-007`, the last Tow-Boot release, for the PINE64 Pinebook Pro (RK3399). It installs to the SPI flash, the same way stock Tow-Boot does.

What it fixes or adds:

- **No more garbage on screen at boot.** The screen stays dark from "Starting kernel" until the kernel's display driver turns the panel on (about 3 s into boot), instead of showing garbage in between.
- **A dimmer Tow-Boot screen.** The stock build runs the backlight at 100%.
- **`/boot` on btrfs** (pbp2c). Tow-Boot can read kernels straight from a btrfs root, including zstd-compressed files, so a snapshot rollback brings the kernel back too.
- **Device-tree overlays.** `FDTOVERLAYS` in `extlinux.conf` works. Stock Tow-Boot is built without overlay support and silently ignores it.
- **Faster boot** (pbp2f): only the internal keyboard's USB controller is started at power-on, about 5.7 s quicker on my Pinebook Pro. "Rescan USB" and "Boot from USB" still use every port.
- A 1 s boot menu countdown instead of 2 s.

Everything else (boot order, menu, saved settings) is the same as stock Tow-Boot `2023.07-007`.

> Not affiliated with the Tow-Boot project or PINE64. Flashing firmware is at your own risk. Read [Recovery](#recovery) first.

## Versions

| Version | Status | What's in it |
|---|---|---|
| **007-pbp2f** | **Tested**: in use on my Pinebook Pro since 2026-10-13 | pbp2c + faster USB start |
| 007-pbp2c | Tested: boots from SPI (2026-10-13), btrfs reading tested | pbp1 + btrfs, with U-Boot's start-up stack moved (see below) |
| 007-pbp1 | Tested, in daily use 2026-10-13 | Backlight fix, dimmer screen, overlays, 1 s countdown |
| ~~007-pbp2~~ | **Broken, withdrawn**: black screen at power-on, needed a maskrom recovery | pbp1 + btrfs + boot timing, without the stack fix |

Prebuilt images are on the [Releases](../../releases) page: `Tow-Boot.spi.bin` (to flash from Linux) and `spi.installer.img` (SD card installer), with SHA-256 sums.

### What happened to 007-pbp2 (and why pbp2c moves the stack)

007-pbp2 gave a black screen and a red LED from power-on, and the SPI flash had to be restored with maskrom; a btrfs-only build (pbp2b) failed the same way. **Cause: the image grew past a memory limit in U-Boot 2023.07.**

U-Boot proper is loaded at `0x200000` with its device tree right after it. At start-up it puts its stack, a 16 KB early heap and its global data just below `CONFIG_CUSTOM_SYS_INIT_SP_ADDR`, which is `0x300000` on the Pinebook Pro. When booting from SPI, SPL also grows the device tree (8 KB of free space plus `/fit-images` entries, `common/spl/spl_fit.c`). pbp1 ends at about `0x2EC930` including that, leaving ~60 KB of stack. btrfs adds ~75 KB of code, so the device tree ran into the early heap and was overwritten before the display came up. Current upstream U-Boot has already moved this stack to `0x03f00000` on Rockchip; pbp2c does the same and leaves ~60 MB of room. An earlier version of this page blamed `CONFIG_BOOTSTAGE`; that was wrong.

`scripts/check-layout.sh` (run by `scripts/build.sh`) checks this for any build and fails pbp2/pbp2b while passing pbp1/pbp2c. Run it before flashing anything you built yourself.

How pbp2c was tested before it was flashed: its first-stage loaders (TPL/SPL) are byte-identical to pbp1's, its U-Boot differs from the chainload-tested pbp2b only in the stack address, and that U-Boot booted Linux from a btrfs filesystem when chainloaded from a working Tow-Boot (`bootm` of a uImage from an extlinux entry). A chainload doesn't reproduce everything SPL does, so in the end it was flashed and booted.

## The changes in detail

### Garbage on screen at boot (patch 0001)

Stock Tow-Boot leaves the eDP panel lit when it starts the kernel. About 1.5 s into boot, Linux turns off every clock and power domain no driver has claimed yet (`clk: Disabling unused clocks`). That cuts the video signal while the backlight stays on, so the panel shows garbage until the display driver (`rockchipdrm`) sets it up again, about 1 s later or more. The usual workaround, `clk_ignore_unused pd_ignore_unused`, broke the display completely on my machine (smeared picture).

The patch turns the backlight PWM (`pwm@ff420000`) off in `board_quiesce_devices()`, which U-Boot calls right before "Starting kernel" (for both `booti` and EFI boots). Linux's `pwm-backlight` then starts with the PWM off and leaves the backlight off until `panel-edp` turns it on with a working picture. The stock Pinebook Pro device tree already links the panel to the backlight, so no device-tree change is needed.

It also sets `default-brightness-level = <40>` (of 255) for the Tow-Boot screen. The Pinebook Pro backlight node has no `brightness-levels`, so U-Boot used 255.

**Downside:** if the kernel dies before the display driver loads, the screen stays dark and you won't see its messages. Use a serial console, or boot a stock Tow-Boot, to debug that.

Tip: put `kms` in `HOOKS` in `/etc/mkinitcpio.conf` (Arch-based distros) so the display driver loads from the initramfs, about 2 s into boot instead of after the root fs is mounted.

### btrfs (pbp2c, patches 0002–0007)

`CONFIG_FS_BTRFS` and the `btrfs`/`btrsubvol` commands are turned on. U-Boot's btrfs reader is **read-only and single-device**, and it reads zlib, lzo and zstd compression.

It opens the filesystem's **default subvolume** (`btrfs subvolume set-default`), or the top level if none is set, the same as the kernel does when you don't pass `subvol=`. So with a typical layout:

```
btrfs (whole partition, p1 or flagged bootable)
├── @            ← set as default subvolume; contains /boot/extlinux/extlinux.conf
├── @home
├── @snapshots
└── ...
```

Tow-Boot finds `/boot/extlinux/extlinux.conf` inside `@` with no extra settings. If you leave `rootflags=subvol=...` **off** the kernel command line, the kernel mounts the same default subvolume. To roll back, point the default at a snapshot (`btrfs subvolume set-default <id> /`): Tow-Boot then loads *that snapshot's* kernel, and the kernel mounts *that snapshot*, so the kernel and its modules always match. The usual separate ext4 `/boot` partition isn't needed.

The btrfs code in U-Boot 2023.07 has bugs that were fixed later in U-Boot master. These are backported unchanged:

| Patch | U-Boot master commit | Fixes |
|---|---|---|
| 0002 | `08404fa208` | Error checking for `btrfs_decompress()` |
| 0003 | `6d6ea52b62` | Reading when a length is given |
| 0004 | `ee1941e4fe` | Out-of-bounds write |
| 0005 | `9204cae093` | Freeing a pointer that's always NULL |
| 0006 | `1a5c8af2d4` | Path not released when a tree search fails |
| 0007 | `6f0719e4c4` | **zstd-compressed small files fail with `zstd_decompress: failed to decompress: 70`** |

0007 matters most: with `compress=zstd`, small files that the running kernel writes (like `extlinux.conf` after you edit it) are stored "inline" in a way 2023.07 can't decompress. It was reported on RK3399 boards (armbian/build#9651, #10208).

Notes:
- I checked the feature flags of a filesystem made with btrfs-progs 7.1 (`extref`, `skinny-metadata`, `no-holes`, `free-space-tree`, `block-group-tree`, zstd) against what U-Boot supports: all fine. `block-group-tree` works because U-Boot never reads block groups. Features U-Boot doesn't know (for example `raid-stripe-tree`, `extent-tree-v2`, `simple-quota`) make it refuse to open the filesystem.
- As with ext4, Tow-Boot only scans partitions with the MBR **bootable flag**. If none has the flag, it only scans partition 1.
- **Tested:** booted a kernel, initramfs and dtb from a zstd-compressed btrfs (single partition, top-level subvolume), including an `extlinux.conf` stored inline and zstd-compressed by the kernel (the 0007 case). Booting from a non-top-level default subvolume like `@` hasn't been tested yet.

### Boot timing (not in any working build yet)

pbp2 had `CONFIG_BOOTSTAGE` and `CONFIG_BOOTSTAGE_FDT` on; pbp2c doesn't, since pbp2 didn't start (for the stack reason above, not because of this). With them, Tow-Boot records the time of each boot stage and adds it to the device tree it hands to the kernel. Nothing is printed on screen. After boot:

```sh
scripts/bootstage.sh
```

prints each stage in milliseconds since power-on, read from `/proc/device-tree/bootstage/`. Handy for comparing, say, `Image` against `Image.gz`, or ext4 against btrfs.

### Faster USB start (pbp2f, patch 0008)

Tow-Boot runs `usb start` at power-on so the boot menu can see the keyboard. U-Boot then starts and scans **all six** USB controllers of the RK3399 (two EHCI, two OHCI, two DWC3/XHCI for the USB 3 and Type-C ports), plus USB storage: `time usb reset` measured **6.4 s** on my Pinebook Pro. The internal keyboard is a low-speed device on USB host0 (EHCI `fe380000` with its OHCI companion `fe3a0000`).

Patch 0008 adds an environment variable to U-Boot: if `usb_only` is set to a space-separated list of controller names, `usb start` only starts those. pbp2f's `preboot` is

```
setenv usb_only usb@fe380000 usb@fe3a0000; usb start; setenv usb_only
```

so only the keyboard's controllers come up at power-on. Any later `usb start` after such a partial start (it's what "Boot from USB" and USB network boot run) brings up **all** controllers first, and `usb reset` ("Rescan USB") always does. Booting from a USB stick should work as before, with the full scan at that point. **Not tested yet:** the keyboard and normal booting are tested, but I haven't booted from USB with pbp2f.

Measured with the arm generic timer (power-on to kernel start, normal boot, same 3 s extlinux menu): **23.5 s with pbp2c, 17.8 s with pbp2f.**

An earlier attempt (pbp2e) disabled the other controllers in U-Boot's device tree instead. That was as fast, but then U-Boot never binds drivers for them, so USB boot was gone even after "Rescan USB".

### Device-tree overlays

`CONFIG_OF_LIBFDT_OVERLAY=y`, so `FDTOVERLAYS /path/a.dtbo /path/b.dtbo` in an `extlinux.conf` entry is applied. Stock 2023.07-007 is built without it and silently ignores the line (the firmware contains the message `config with overlays but CONFIG_OF_LIBFDT_OVERLAY not set`). Overlays can only add or change properties, not delete them. If you need to delete one, merge the dtb yourself with `fdtoverlay` + `fdtput -d`.

## Installing

Check what you're replacing first: this firmware goes into the 16 MiB SPI flash chip, not the eMMC or SD card.

### From a running Linux system on the Pinebook Pro

Needs the kernel's SPI flash driver (most distro kernels have it; `cat /proc/mtd` should list the SPI flash as `mtd0`) and `flashcp` from `mtd-utils`.

```sh
# 1. Back up the whole chip and keep the file somewhere safe (not only on the laptop)
sudo dd if=/dev/mtd0ro of=mtd0-backup.img bs=1M
# 2. Check the download
sha256sum Tow-Boot.spi.bin        # compare with the release page
# 3. Flash (only touches the first ~1.8 MB; Tow-Boot's saved settings at 0xFE0000 are left alone)
sudo flashcp -v Tow-Boot.spi.bin /dev/mtd0
# 4. Read it back and compare
sudo cmp -n $(stat -c%s Tow-Boot.spi.bin) /dev/mtd0ro Tow-Boot.spi.bin && echo OK
```

To undo: `sudo flashcp -v mtd0-backup.img /dev/mtd0`.

### From an SD card

Use `spi.installer.img` the same way as stock Tow-Boot: unpack it (`xz -d spi.installer.img.xz`), write it to an SD card, boot it, and pick **"Flash firmware to SPI"**. See the [Tow-Boot Pinebook Pro page](https://tow-boot.org/devices/pine64-pinebookPro.html). The RK3399 starts from SPI first, then eMMC, then SD, so if there's already a bootloader in SPI or on the eMMC, you may have to keep it from starting before the installer can run.

## Recovery

If the laptop doesn't start after flashing (no Tow-Boot screen at all), the SPI flash has to be rewritten from another computer: put the RK3399 into **maskrom** mode and use `rkdeveloptool` over USB-C. See the [PINE64 wiki](https://wiki.pine64.org/wiki/Pinebook_Pro). Keep your `mtd0-backup.img` on another machine before you flash anything.

If Tow-Boot starts but your OS doesn't, that's a boot config problem, not the firmware. Pick another entry or device from the Tow-Boot menu.

## Good to know about Tow-Boot on the Pinebook Pro

These hold for stock Tow-Boot 2023.07-007 and this build:

- **Boot order** is `mmc0 mmc1 nvme0 usb0 pxe dhcp sf0`, where **mmc0 is the eMMC** and mmc1 the SD card. A bootable eMMC always wins; to boot an SD card, pick it in the Tow-Boot menu at power-on.
- Each device is checked for `/extlinux/extlinux.conf`, then `/boot/extlinux/extlinux.conf` (plus `boot.scr` in the same places). Only partitions with the **bootable flag** are scanned, or partition 1 if none has it.
- **`DEFAULT` in `extlinux.conf` is ignored**: the menu starts on the first entry marked `MENU DEFAULT`, or the first entry if none is marked. Put your default entry first and mark it `MENU DEFAULT`.
- `TIMEOUT` is in tenths of a second.
- `Image.gz` kernels work: Tow-Boot unpacks them (`kernel_comp_size` is 32 MB).
- `sf0` reads a boot script from the last 8 KiB of the SPI chip, which is inside the saved-settings area, so it does nothing useful.

## Building

```sh
scripts/build.sh pbp2f     # or pbp2c, pbp1
```

It checks out Tow-Boot `release-2023.07-007` (which builds [Tow-Boot/U-Boot](https://github.com/Tow-Boot/U-Boot) tag `tb-2023.07-007`) into `build/`, applies the patches and config from `nix/<variant>.nix`, puts the results in `out/<variant>/`, and runs `scripts/check-layout.sh` on the image. It uses `nix-build` if you have Nix. Otherwise it runs Nix in a `podman`/`docker` container, with the Nix store kept in a volume called `towboot-nix`. It cross-compiles on x86_64; the first build takes a while.

The full U-Boot configs of the released images are in `configs/`.

Rebuilding gives the same firmware as the release images: everything up to the small `SBOM` block at the very end of `Tow-Boot.spi.bin` matches byte for byte. That block holds build info, including the Nix store path, which changes with the location of the patch files.

## Credits and license

- [Tow-Boot](https://github.com/Tow-Boot/Tow-Boot) by Samuel Dionne-Riel and contributors, built on [U-Boot](https://source.denx.de/u-boot/u-boot).
- Patches 0002–0007 are by their original authors (named in each patch) and come unchanged from U-Boot master. 0007 is by Cole Munz, reviewed by Qu Wenruo.
- Like U-Boot, everything here is GPL-2.0 (see `LICENSE`). Tow-Boot's own build files are MIT.
