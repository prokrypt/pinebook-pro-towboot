#!/bin/sh
# Print the boot timing Tow-Boot hands to the kernel in /proc/device-tree/bootstage.
# Needs a build with CONFIG_BOOTSTAGE and CONFIG_BOOTSTAGE_FDT: 007-pbp2y and later.
# Times are microseconds since TPL started (arm generic timer); "accum" lines are durations.
#
#   scripts/bootstage.sh
set -eu

dir=${BOOTSTAGE_DIR:-/proc/device-tree/bootstage}
[ -d "$dir" ] || { echo "no $dir: firmware built without BOOTSTAGE_FDT?" >&2; exit 1; }

u32() { od -An -tu1 "$1" | awk '{for (i = 1; i <= NF; i++) v = v * 256 + $i} END {print v}'; }

for d in "$dir"/*/; do
	name=$(tr -d '\0' < "$d/name")
	if [ -f "$d/mark" ]; then
		printf '%s mark %s\n' "$(u32 "$d/mark")" "$name"
	elif [ -f "$d/accum" ]; then
		printf '%s accum %s\n' "$(u32 "$d/accum")" "$name"
	fi
done | sort -n | awk '
	{ name = $0; sub(/^[0-9]+ [a-z]+ /, "", name) }
	$2 == "mark"  { printf "%10.3f ms  +%8.3f ms  %s\n", $1 / 1000, ($1 - prev) / 1000, name; prev = $1; next }
	              { acc[++n] = sprintf("%10.3f ms  (total) %s", $1 / 1000, name) }
	END { if (n) { print "\nAccumulated:"; for (i = 1; i <= n; i++) print acc[i] } }'
