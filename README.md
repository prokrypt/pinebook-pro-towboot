# Tow-Boot for the Pinebook Pro, with fixes

A small set of patches on top of [Tow-Boot](https://tow-boot.org) `2023.07-007`, the last Tow-Boot release, for the PINE64 Pinebook Pro (RK3399). It installs to the SPI flash, the same way stock Tow-Boot does.

What it fixes or adds:

- **No more garbage on screen at boot.** The screen stays dark from "Starting kernel" until the kernel's display driver turns the panel on (about 3 s into boot), instead of showing garbage in between.
- **A dimmer Tow-Boot screen.** The stock build runs the backlight at 100%.
- **`/boot` on btrfs** (pbp2c). Tow-Boot can read kernels straight from a btrfs root, including zstd-compressed files, so a snapshot rollback brings the kernel back too.
- **Device-tree overlays.** `FDTOVERLAYS` in `extlinux.conf` works. Stock Tow-Boot is built without overlay support and silently ignores it.
- **Faster boot** (pbp2f): only the internal keyboard's USB controller is started at power-on, about 5.7 s quicker on my Pinebook Pro. "Rescan USB" and "Boot from USB" still use every port.
- **Less battery drain in suspend** (pbp2m): the big-core and GPU regulators are switched off during deep sleep, as Rockchip's own firmware does (TF-A patch).
- **External USB keyboards work in the Tow-Boot menu** next to the internal one (pbp2k; right USB-A port, after "Rescan USB"; [Tow-Boot#153](https://github.com/Tow-Boot/Tow-Boot/issues/153)).
- **The touchpad no longer freezes the keyboard** in the Tow-Boot menu (pbp2i; a bug in stock Tow-Boot since 2021, [Tow-Boot#57](https://github.com/Tow-Boot/Tow-Boot/issues/57)).
- **Faster eMMC** (pbp2n): HS200 at up to 200 MHz instead of 25 MHz, so the kernel and initramfs load faster.
- **Faster SD card** (pbp2g and later): 50 MHz instead of 20 MHz in Tow-Boot, so booting from SD loads about 65% faster.
- A 1 s boot menu countdown instead of 2 s.

Everything else (boot order, menu, saved settings) is the same as stock Tow-Boot `2023.07-007`.

> Not affiliated with the Tow-Boot project or PINE64. Flashing firmware is at your own risk. Read [Recovery](#recovery) first.

## Versions

| Version | Status | What's in it |
|---|---|---|
| **007-pbp2n** | **Tested**: in use on my Pinebook Pro since 2026-10-15 | pbp2m + **eMMC in HS200** (patch 0024) |
| 007-pbp2m | Tested 2026-10-15 | pbp2k + **big-core and GPU regulators off in suspend** (TF-A patch `tfa-0001`) |
| ~~007-pbp2l~~ | Not released: its TF-A change never took effect (see below) | pbp2k + first try of the suspend change |
| 007-pbp2k | Tested: in use on my Pinebook Pro 2026-10-13 to 10-15 | pbp2j + **external USB keyboards work** next to the internal one (0023, fixes Tow-Boot#153) |
| 007-pbp2j | Tested 2026-10-13 | pbp2i + upstream XHCI fixes (no reset on USB 3 timeouts) + keyboard fallback |
| 007-pbp2i | Tested 2026-10-13 | pbp2h + **touchpad no longer freezes the keyboard** in the menu (0011, fixes Tow-Boot#57) |
| 007-pbp2h | Tested 2026-10-13 | pbp2f + SD at 50 MHz + one more btrfs fix (0010); version labels fixed |
| 007-pbp2f | Tested: in use on my Pinebook Pro 2026-10-13 | pbp2c + faster USB start |
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
| 0010 | `c331efd087` | Crash in `btrsubvol` when a subvolume can't be read (pbp2h; not used when booting) |

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

**If the internal keyboard is missing or broken** (pbp2j, patch 0022): when the keyboard-only start at power-on finds no USB keyboard, U-Boot starts all controllers (`no USB keyboard found, starting all controllers...`), so a keyboard in the **right** USB-A port should work instead, as with stock Tow-Boot. Normally the internal keyboard is found and nothing changes. Tested by simulating it from the console (`usb stop; setenv usb_only usb@fe800000; usb start`): the full start ran and the keyboard came back. An external keyboard as the only keyboard isn't tested, since the internal one can't easily be unplugged.

**External keyboards next to the internal one** (pbp2k): only the internal keyboard's controllers start at power-on, so pick **"Rescan USB"** first; after that a USB keyboard in the **right** USB-A port works alongside the internal one (patch 0023, see below). The left (USB 3) port can't take a keyboard. The USB-A ports aren't scanned at power-on (right port = `usb@fe3c0000` behind an internal hub that also has the webcam, left port = `usb@fe900000`) because that would cost boot time. To scan everything at power-on anyway, set `preboot` back from the Firmware Console: `setenv preboot usb start; saveenv` (undo with `env default preboot; saveenv`).

An earlier attempt (pbp2e) disabled the other controllers in U-Boot's device tree instead. That was as fast, but then U-Boot never binds drivers for them, so USB boot was gone even after "Rescan USB".

### SD card at 50 MHz (pbp2g and later, patch 0009)

U-Boot's Pinebook Pro device tree caps the SD card at 20 MHz (and the eMMC at 25 MHz), since Pinebook Pro support was first added in 2020, with no reason given. Other RK3399 boards don't cap the SD card, and Rockchip's own Android device tree for the Pinebook Pro runs it at 50 MHz. Patch 0009 sets 50 MHz (SD high speed). Measured on my 128 GB card, loading from btrfs:

| File | 20 MHz | 50 MHz |
|---|---|---|
| initramfs, 23 MB | 3.69 s | 2.19 s |
| kernel `Image`, 50 MB | 6.63 s | 4.01 s |

The change also lands in TPL's and SPL's device trees (the `sdmmc` node is in all phases), but they don't touch the SD card when booting from SPI. The eMMC cap (25 MHz, ~22 MiB/s) is unchanged.

### Touchpad froze the keyboard (pbp2i, patch 0011)

The Pinebook Pro's keyboard and touchpad are one USB device: interface 0 is a boot keyboard (interrupt endpoint `0x81`), interface 1 a generic HID interface for the touchpad (endpoint `0x82`). U-Boot's `usb_kbd` driver only ever polls `0x81`. Once the touchpad is touched, its report sits unread on `0x82`, and the keyboard chip then stops sending keyboard reports too, so the menu looked frozen until "Rescan USB" (which needs the keyboard...).

Patch 0011 makes `usb_kbd` also set up an interrupt queue for the first interrupt-IN endpoint on another interface of the keyboard's device, and read and throw away whatever arrives on it each time the keyboard is polled. Only active with `CONFIG_SYS_USB_EVENT_POLL_VIA_INT_QUEUE` (Tow-Boot's setting); plain keyboards are unaffected. Tested: with pbp2h, touching the touchpad froze the keyboard; with pbp2i it keeps working.

### Why external keyboards don't work, and XHCI fixes (pbp2j)

Two U-Boot limitations, both still in upstream master as of 2026:

1. Every USB keyboard registers as console device `usbkbd`, and `usb_kbd_testc()`/`usb_kbd_getc()` look the device up again **by that name**, which always returns the first one: on a laptop, the internal keyboard. A second keyboard is set up and registered (`coninfo` lists two `usbkbd`) but never polled. **Fixed in pbp2k (patch 0023):** `testc`/`getc` use the device they're called with, extra keyboards are named `usbkbd1`, `usbkbd2`, … and appended to `$stdin`, and each keyboard has its own poll timer. Tested: after "Rescan USB", the internal keyboard and a USB keyboard in the right port both work.
2. The left USB-A port is a USB 3 (XHCI) controller (`usb@fe900000`). XHCI has no `create_int_queue`, which Tow-Boot's keyboard polling (`CONFIG_SYS_USB_EVENT_POLL_VIA_INT_QUEUE`) needs, so a keyboard there is rejected ("Failed to get keyboard state from device"); XHCI interrupt transfers also ignore `nonblock`. The right port (`usb@fe3c0000`, EHCI behind an internal hub that also has the webcam) can take a keyboard.

In U-Boot 2023.07 an XHCI event timeout **panics and resets the board**, a likely cause of "Rescan USB" reboots ([Tow-Boot#141](https://github.com/Tow-Boot/Tow-Boot/issues/141)). Patches 0012–0021 backport upstream's XHCI robustness fixes, mostly Hector Martin's October 2023 series (`3aba92c9dd`, `8d1e03f984`, `2526cd9932`, `6f64f0ae23`, `9d88bd4dcf`, `fb5502be25`, `2fd7037122` "Do not panic on event timeouts", `a14843fdac`, `0b6775c402`, `ba94fb3003`). After that, "Rescan USB" (which starts and scans both XHCI controllers every time) came back to the menu without a reboot in 4 tries, with a USB keyboard in the right (USB 2.0) port; the USB 3 port itself was empty, so a device on the USB 3 port during a rescan is still untested. USB drives use bulk transfers, which XHCI does support, so both USB-A ports should boot a USB drive; **not tested yet** (no bootable stick at hand).

### Big-core and GPU regulators off in suspend (pbp2m, TF-A patch)

The big CPU cluster (`vdd_cpu_b`, Silergy SYR827) and the GPU (`vdd_gpu`, SYR828) have their own regulators, fed from the battery side, so the RK808 PMIC going to sleep doesn't cut them: they stayed on all night in deep suspend. Each has a VSEL pin that picks one of two voltage registers: `CPU_B_SLEEP_H` on **GPIO1_C1** and `GPU_SLEEP_H` on **GPIO1_B6**. Linux already marks register 1 "off in suspend" (`fcs,suspend-voltage-selector = <1>` plus `regulator-off-in-suspend` in the mainline device tree), but nothing ever drives the pins high, so register 1 is never used. Rockchip's own BL31 does: the vendor device tree has `rockchip,power-ctrl = <&gpio1 17 GPIO_ACTIVE_HIGH>, <&gpio1 14 GPIO_ACTIVE_HIGH>`.

Mainline TF-A has the same mechanism (`suspend_gpio()`/`resume_gpio()` in `plat/rockchip/rk3399/drivers/pmu/pmu.c`, run as the very last step before sleep and the first on wake), but only fills the pin list from coreboot's `bl_aux` parameters. U-Boot passes none, and with `CONFIG_SPL_ATF_NO_PLATFORM_PARAM=y` (the RK3399 default) not even a device tree. `patches/tfa-0001-pbp-suspend-gpios.patch` (against TF-A v2.9, the version Tow-Boot 007 builds) adds the two pins in `params_early_setup()`. It also waits 1 ms after the pins drop on wake, so the regulators can soft-start before TF-A touches the big cluster. The nix file overrides `Tow-Boot.builder.additionalArguments.BL31` with the patched TF-A. pbp2l had a first version that only added the pins when U-Boot's device tree said Pinebook Pro. U-Boot never passes one, so that version did nothing.

Tested 2026-10-15: suspend and resume work, all six cores and the GPU come back, and after a wake both pins read as outputs, low, which only TF-A's `resume_gpio()` leaves them as. How much it saves isn't measured yet. Before the change, suspend drained about 0.46 %/h on my machine, and Rockchip's firmware reportedly gets 0.2–0.3 %/h.

### Faster eMMC: HS200 (pbp2n, patch 0024), and why not HS400

The Pinebook Pro's U-Boot device tree capped the eMMC at **25 MHz** (`max-frequency` on `&sdhci` in `rk3399-pinebook-pro-u-boot.dtsi`). The cap dates from the first Pinebook Pro commit (2020), with no reason given. Every other RK3399 board gets 200 MHz from `rk3399-u-boot.dtsi`, and the board DT already allows HS200 (`mmc-hs200-1_8v`). At 25 MHz, the kernel + initramfs (about 42 MB) took about 1.9 s to load. Patch 0024 sets 200 MHz, and U-Boot then uses HS200, as Linux does.

**HS400 doesn't work on this board** (tested 2026-10-15 with a SanDisk DA4064 eMMC, which reports HS400 and Enhanced Strobe support). Rockchip's own Android device tree for the Pinebook Pro only enables HS200 too.
- Linux with `mmc-hs400-1_8v` + `mmc-hs400-enhanced-strobe` couldn't find its root filesystem.
- U-Boot with HS400 Enhanced Strobe loaded the kernel fine, but Linux (in HS200) then failed to take over the eMMC and didn't finish booting.

HS200 in U-Boot followed by HS200 in Linux works.

**Boot time** (power-on to kernel start, my Pinebook Pro, `/boot` on btrfs):

| Kernel | How it's stored | Power-on → kernel |
|---|---|---|
| `Image.gz` | gzip | 17.8 s |
| `Image` | btrfs zstd compression | 19.2 s |
| `Image` | btrfs, no compression | **15.3 s** |

With the eMMC at HS200, reading the raw 48 MB kernel is faster than unpacking it. U-Boot's gunzip and its btrfs zstd decompression are both slow. To keep `/boot` uncompressed on btrfs, run `chattr +m /boot` (new files inherit it). Then rewrite existing files with `cp --reflink=never` and `mv`; a plain `cp` reflinks and keeps the old compressed data.

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

**If you ever saved Tow-Boot settings** (`saveenv` in its console, or `fw_setenv` from Linux), they live in the SPI flash at `0xFE0000`, which flashing doesn't touch, and they override the new build's defaults: you'd keep your old `preboot` (no USB speed-up) and `bootdelay`. After flashing, reset them from the Firmware Console with `env default -a; saveenv`. If you never saved settings, the area is blank (`0xFF`) and there's nothing to do.

### From an SD card

Use `spi.installer.img` the same way as stock Tow-Boot: unpack it (`xz -d spi.installer.img.xz`), write it to an SD card, boot it, and pick **"Flash firmware to SPI"**. See the [Tow-Boot Pinebook Pro page](https://tow-boot.org/devices/pine64-pinebookPro.html). The RK3399 starts from SPI first, then eMMC, then SD, so if there's already a bootloader in SPI or on the eMMC, you may have to keep it from starting before the installer can run.

## Recovery

If the laptop doesn't start after flashing (no Tow-Boot screen at all), the SPI flash has to be rewritten from another computer: put the RK3399 into **maskrom** mode and use `rkdeveloptool` over USB-C. See the [PINE64 wiki](https://wiki.pine64.org/wiki/Pinebook_Pro). Keep your `mtd0-backup.img` on another machine before you flash anything.

If Tow-Boot starts but your OS doesn't, that's a boot config problem, not the firmware. Pick another entry or device from the Tow-Boot menu.

## Known issues (also in stock Tow-Boot)

These are open bugs in stock Tow-Boot on the Pinebook Pro, and this build has them too:

- ~~Touching the touchpad freezes the keyboard in the Tow-Boot menu~~ ([Tow-Boot#57](https://github.com/Tow-Boot/Tow-Boot/issues/57)): **fixed in pbp2i**, see "Touchpad froze the keyboard" above. In older builds and stock Tow-Boot: don't touch the touchpad in the menu.
- **"Rescan USB" sometimes reboots** ([Tow-Boot#141](https://github.com/Tow-Boot/Tow-Boot/issues/141)), intermittently. Probably fixed in pbp2j (XHCI no longer panics on timeouts, see above): not reproduced in 4 rescans. Before that I also once saw a reboot right after pressing Enter in the console.
- ~~External USB keyboards don't work in the menu~~ ([Tow-Boot#153](https://github.com/Tow-Boot/Tow-Boot/issues/153)): **fixed in pbp2k** for the right USB-A port (after "Rescan USB"); the left (USB 3) port still can't take a keyboard.

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
scripts/build.sh pbp2n     # or pbp2m, pbp2l, pbp2k, pbp2j, pbp2i, pbp2h, pbp2f, pbp2c, pbp1
```

It checks out Tow-Boot `release-2023.07-007` (which builds [Tow-Boot/U-Boot](https://github.com/Tow-Boot/U-Boot) tag `tb-2023.07-007`) into `build/`, applies the patches and config from `nix/<variant>.nix`, puts the results in `out/<variant>/`, and runs `scripts/check-layout.sh` on the image. It uses `nix-build` if you have Nix. Otherwise it runs Nix in a `podman`/`docker` container, with the Nix store kept in a volume called `towboot-nix`. It cross-compiles on x86_64; the first build takes a while.

The full U-Boot configs of the released images are in `configs/`.

Rebuilding gives the same firmware as the release images: everything up to the small `SBOM` block at the very end of `Tow-Boot.spi.bin` matches byte for byte. That block holds build info, including the Nix store path, which changes with the location of the patch files.

## Credits and license

- [Tow-Boot](https://github.com/Tow-Boot/Tow-Boot) by Samuel Dionne-Riel and contributors, built on [U-Boot](https://source.denx.de/u-boot/u-boot).
- Patches 0002–0007 are by their original authors (named in each patch) and come unchanged from U-Boot master. 0007 is by Cole Munz, reviewed by Qu Wenruo.
- Like U-Boot, everything here is GPL-2.0 (see `LICENSE`). Tow-Boot's own build files are MIT.
