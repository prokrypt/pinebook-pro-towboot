#!/bin/sh
# Check that U-Boot proper + its device tree fit below U-Boot's start-up
# stack and early heap. If they don't, the board doesn't start at all
# (black screen, maskrom recovery needed). This is what broke 007-pbp2.
#
#   scripts/check-layout.sh out/pbp2c/binaries/Tow-Boot.spi.bin configs/pbp2c.spi.config
#
# Layout at start-up (U-Boot 2023.07, Rockchip SPI boot):
#   CONFIG_TEXT_BASE                U-Boot proper, then its device tree
#   + 8 KB + /fit-images            SPL grows the device tree before handing over
#                                   (common/spl/spl_fit.c: fdt_shrink_to_minimum(..., 8192))
#   ... stack, growing down ...
#   SP - SYS_MALLOC_F_LEN - gd      early heap + global_data
#   CONFIG_CUSTOM_SYS_INIT_SP_ADDR  start-up stack pointer
# Needs: fdtget (dtc) or python3, and the build's .config.
set -eu

img=$1 cfg=$2
val() { sed -n "s/^CONFIG_$1=//p" "$cfg"; }

text=$(val TEXT_BASE)
sp=$(val CUSTOM_SYS_INIT_SP_ADDR)
mallocf=$(val SYS_MALLOC_F_LEN)
offs=$(val SYS_SPI_U_BOOT_OFFS)
[ -n "$text" ] && [ -n "$sp" ] && [ -n "$mallocf" ] && [ -n "$offs" ] ||
	{ echo "missing TEXT_BASE/CUSTOM_SYS_INIT_SP_ADDR/SYS_MALLOC_F_LEN/SYS_SPI_U_BOOT_OFFS in $cfg" >&2; exit 2; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
dd if="$img" of="$tmp" bs=$((offs)) skip=1 status=none
if command -v fdtget >/dev/null; then
	fdt=$(fdtget "$tmp" /configurations/config-1 fdt)
	ub=$(fdtget -tu "$tmp" /images/u-boot data-size)
	dt=$(fdtget -tu "$tmp" "/images/$fdt" data-size)
else
	# No dtc installed: read the same values from the FIT header with python3
	set -- $(python3 - "$tmp" <<'PY'
import struct, sys
b = open(sys.argv[1], 'rb').read()
magic, total, off_struct, off_strings = struct.unpack('>4I', b[:16])
assert magic == 0xd00dfeed, 'no FIT image at CONFIG_SYS_SPI_U_BOOT_OFFS'
props, path, pos = {}, [], off_struct
while True:
    tag, = struct.unpack('>I', b[pos:pos + 4]); pos += 4
    if tag == 1:                                   # BEGIN_NODE
        end = b.index(b'\0', pos); path.append(b[pos:end].decode())
        pos = (end + 4) & ~3
    elif tag == 2:                                 # END_NODE
        path.pop()
    elif tag == 3:                                 # PROP
        ln, nameoff = struct.unpack('>II', b[pos:pos + 8]); pos += 8
        name = b[off_strings + nameoff:b.index(b'\0', off_strings + nameoff)].decode()
        props['/'.join(path) + '/' + name] = b[pos:pos + ln]
        pos = (pos + ln + 3) & ~3
    elif tag == 9:                                 # END
        break
fdt = props['/configurations/config-1/fdt'].rstrip(b'\0').decode()
u32 = lambda k: struct.unpack('>I', props[k])[0]
print(fdt, u32('/images/u-boot/data-size'), u32('/images/%s/data-size' % fdt))
PY
)
	fdt=$1 ub=$2 dt=$3
fi

spl_extra=$((8192 + 1024))     # SPL's padding + /fit-images nodes
gd=1024                        # sizeof(struct global_data), rounded up
stack=$((32 * 1024))           # minimum stack to leave (pbp1 leaves ~60 KB and works)

end=$((text + ub + dt + spl_extra))
limit=$((sp - mallocf - gd - stack))
printf 'U-Boot 0x%x + %d, device tree %d (+%d from SPL) -> ends 0x%x\n' "$((text))" "$ub" "$dt" "$spl_extra" "$end"
printf 'stack at 0x%x, early heap 0x%x, keep %d KB of stack -> limit 0x%x\n' "$((sp))" "$((mallocf))" $((stack / 1024)) "$limit"
if [ "$end" -gt "$limit" ]; then
	printf 'FAIL: %d bytes too big. Do not flash this image.\n' $((end - limit))
	exit 1
fi
printf 'OK: %d KB to spare\n' $(((limit - end) / 1024))
