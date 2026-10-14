#!/bin/sh
# Build a variant (pbp1 or pbp2c) of this Tow-Boot for the Pinebook Pro.
#
#   scripts/build.sh pbp2c
#
# Uses nix-build if Nix is installed, otherwise podman (or docker) with the
# nixos/nix image. Works on x86_64 (cross-compiles) and aarch64 hosts.
# Output: out/<variant>/ (binaries/Tow-Boot.spi.bin, spi.installer.img, config/)
set -eu

variant=${1:-pbp2c}
repo=$(cd "$(dirname "$0")/.." && pwd)
nixfile=$repo/nix/$variant.nix
[ -f "$nixfile" ] || { echo "unknown variant: $variant (see nix/)" >&2; exit 1; }

tag=release-2023.07-007
src=$repo/build/Tow-Boot
if [ ! -d "$src" ]; then
	git clone --depth 1 --branch "$tag" https://github.com/Tow-Boot/Tow-Boot.git "$src"
fi
mkdir -p "$repo/out"
rm -rf "$repo/out/$variant"

if command -v nix-build >/dev/null; then
	nix-build "$src" -A pine64-pinebookPro --arg configuration "$nixfile" \
		-o "$repo/build/result-$variant"
	cp -rL "$repo/build/result-$variant" "$repo/out/$variant"
else
	engine=$(command -v podman || command -v docker) ||
		{ echo "need nix-build, podman or docker" >&2; exit 1; }
	# The Nix store lives in a named volume so later builds are fast.
	# Nix's own sandbox doesn't work inside an unprivileged container.
	"$engine" run --rm -v towboot-nix:/nix -v "$repo:/repo:Z" -w /repo \
		docker.io/nixos/nix sh -c "
			nix-build --option sandbox false build/Tow-Boot -A pine64-pinebookPro \
				--arg configuration /repo/nix/$variant.nix -o build/result-$variant &&
			cp -rL build/result-$variant out/$variant"
fi

chmod -R u+w "$repo/out/$variant"
sha256sum "$repo/out/$variant/binaries/Tow-Boot.spi.bin"
# Refuse images that would overlap U-Boot's start-up stack (see check-layout.sh)
"$repo/scripts/check-layout.sh" "$repo/out/$variant/binaries/Tow-Boot.spi.bin" \
	"$repo/out/$variant/config/spi.config"
