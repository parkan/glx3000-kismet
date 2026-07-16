#!/bin/sh
# Generate kismet's OUI database (MAC prefix -> vendor) from the IEEE registry.
#
# Without this file kismet logs "No OUI files were available" and every device
# shows manuf "Unknown" -- which matters here, because an SSID can be hidden but
# an OUI can't: vendor-by-MAC is how you identify phone hotspots.
#
# Format is what kismet's own tools/create_oui_db.py emits: gzipped, one
# "XX:XX:XX<TAB>Vendor" per line, sorted. That tool also merges wireshark and
# nmap, but IEEE MA-L alone is 39751 of its 39975 entries (99.4%) and needs no
# python/requests, so we stick to the registry.
#
# kismet_package.conf already points at /etc/kismet/kismet_manuf.txt.gz, so
# dropping this into files/etc/kismet/ needs no config change.
set -e

out="${1:?usage: $0 <output.gz>}"
mkdir -p "$(dirname "$out")"

wget -qO- https://standards-oui.ieee.org/oui/oui.txt \
	| sed -n 's/^\([0-9A-F][0-9A-F]\)-\([0-9A-F][0-9A-F]\)-\([0-9A-F][0-9A-F]\)[[:space:]]*(hex)[[:space:]]*\(.*\)$/\1:\2:\3\t\4/p' \
	| sed 's/[[:space:]]*$//' \
	| sort \
	| gzip -9 > "$out.tmp"

# only publish a plausible db -- a truncated fetch must not silently ship
n=$(zcat "$out.tmp" | wc -l)
if [ "$n" -lt 30000 ]; then
	rm -f "$out.tmp"
	echo "gen-oui-db: only $n OUIs, refusing to write a truncated db" >&2
	exit 1
fi
mv "$out.tmp" "$out"
echo "gen-oui-db: $n OUIs -> $out"
