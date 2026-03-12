#!/bin/sh
# feed iw scan results into kismet's scan report API
# runs in a loop, posting all visible APs every $INTERVAL seconds

KISMET_URL="http://127.0.0.1:2501"
KISMET_AUTH="survey:survey"
SOURCE_UUID="44444444-0000-0000-0000-000000000000"
SOURCE_NAME="iw-scan-feeder"
INTERVAL="${SCAN_INTERVAL:-10}"

# wait for kismet to come up
wait_for_kismet() {
	i=0; while [ "$i" -lt 30 ]; do i=$((i + 1))
		curl -s -u "$KISMET_AUTH" "$KISMET_URL/system/status.json" >/dev/null 2>&1 && return 0
		sleep 1
	done
	echo "kismet not responding after 30s" >&2
	return 1
}

# parse iw scan output into kismet scan_report json
# reads from stdin, writes json to stdout
parse_iw_scan() {
	awk -v name="$SOURCE_NAME" -v uuid="$SOURCE_UUID" '
	BEGIN { first = 1; printf "{\"source_name\":\"%s\",\"source_uuid\":\"%s\",\"reports\":[", name, uuid }
	/^BSS / {
		if (bssid != "") {
			if (!first) printf ","
			printf "{\"bssid\":\"%s\"", bssid
			if (ssid != "") printf ",\"ssid\":\"%s\"", ssid
			if (freq != "") printf ",\"freqkhz\":%d", freq * 1000
			if (signal != "") printf ",\"signal\":%d", signal
			if (chan != "") printf ",\"channel\":\"%s\"", chan
			first = 0
			printf "}"
		}
		bssid = ""; ssid = ""; freq = ""; signal = ""; chan = ""
		gsub(/[()].*/, "", $2)
		bssid = toupper($2)
	}
	/freq:/ { freq = $2 }
	/signal:/ { signal = int($2) }
	/SSID:/ {
		ssid = ""
		for (i = 2; i <= NF; i++) ssid = ssid (i > 2 ? " " : "") $i
		gsub(/"/, "\\\"", ssid)
	}
	/DS Parameter set: channel/ { chan = $NF }
	/primary channel:/ { if (chan == "") chan = $NF }
	END {
		if (bssid != "") {
			if (!first) printf ","
			printf "{\"bssid\":\"%s\"", bssid
			if (ssid != "") printf ",\"ssid\":\"%s\"", ssid
			if (freq != "") printf ",\"freqkhz\":%d", freq * 1000
			if (signal != "") printf ",\"signal\":%d", signal
			if (chan != "") printf ",\"channel\":\"%s\"", chan
			printf "}"
		}
		printf "]}"
	}
	'
}

# get list of wireless interfaces
get_interfaces() {
	iw dev 2>/dev/null | awk '/Interface/ { print $2 }'
}

# allow sourcing for tests without running the main loop
[ "${IW_SCAN_FEEDER_SOURCED:-}" = 1 ] && return 0 2>/dev/null

wait_for_kismet || exit 1

while true; do
	scan_output=""
	for iface in $(get_interfaces); do
		result=$(iw dev "$iface" scan 2>&1)
		if [ -n "$result" ]; then
			scan_output="${scan_output}${result}
"
		fi
	done

	if [ -n "$scan_output" ]; then
		echo "$scan_output" | parse_iw_scan | \
			curl -s -u "$KISMET_AUTH" \
				-X POST "$KISMET_URL/phy/phy80211/scan/scan_report.cmd" \
				-H "Content-Type: application/json" \
				-d @- >/dev/null 2>&1
	fi

	sleep "$INTERVAL"
done
