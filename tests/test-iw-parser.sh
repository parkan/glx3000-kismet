#!/bin/sh
# test the iw scan output parser from iw-scan-feeder.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# source the feeder script without running the main loop
IW_SCAN_FEEDER_SOURCED=1 . "$SCRIPT_DIR/../files/usr/bin/iw-scan-feeder.sh"
SOURCE_NAME="test-source"
SOURCE_UUID="00000000-0000-0000-0000-000000000000"

fail=0

check() {
	name="$1"
	expected="$2"
	actual="$3"
	if [ "$expected" = "$actual" ]; then
		echo "ok: $name"
	else
		echo "FAIL: $name"
		echo "  expected: $expected"
		echo "  actual:   $actual"
		fail=1
	fi
}

jq_field() {
	python3 -c "import sys,json; print(json.load(sys.stdin)$1)"
}

# --- test: single AP ---

result=$(cat <<'IW' | parse_iw_scan
BSS aa:bb:cc:dd:ee:ff(on wlan0)
	freq: 2412
	signal: -62.00 dBm
	SSID: TestNetwork
	DS Parameter set: channel 1
IW
)

check "single AP - bssid" \
	"AA:BB:CC:DD:EE:FF" \
	"$(echo "$result" | jq_field "['reports'][0]['bssid']")"

check "single AP - ssid" \
	"TestNetwork" \
	"$(echo "$result" | jq_field "['reports'][0]['ssid']")"

check "single AP - freqkhz" \
	"2412000" \
	"$(echo "$result" | jq_field "['reports'][0]['freqkhz']")"

check "single AP - signal" \
	"-62" \
	"$(echo "$result" | jq_field "['reports'][0]['signal']")"

check "single AP - channel" \
	"1" \
	"$(echo "$result" | jq_field "['reports'][0]['channel']")"

check "single AP - report count" \
	"1" \
	"$(echo "$result" | jq_field "['reports'].__len__()")"

# --- test: multiple APs ---

result=$(cat <<'IW' | parse_iw_scan
BSS aa:bb:cc:dd:ee:ff(on wlan0) -- associated
	freq: 2412
	signal: -45.00 dBm
	SSID: HomeNetwork
	DS Parameter set: channel 1
BSS 11:22:33:44:55:66(on wlan0)
	freq: 5180
	signal: -71.00 dBm
	SSID: Neighbor5G
	DS Parameter set: channel 36
BSS de:ad:be:ef:00:01(on wlan0)
	freq: 2437
	signal: -83.00 dBm
	SSID: CoffeeShop Free WiFi
	DS Parameter set: channel 6
IW
)

check "multi AP - count" \
	"3" \
	"$(echo "$result" | jq_field "['reports'].__len__()")"

check "multi AP - second bssid" \
	"11:22:33:44:55:66" \
	"$(echo "$result" | jq_field "['reports'][1]['bssid']")"

check "multi AP - third ssid with spaces" \
	"CoffeeShop Free WiFi" \
	"$(echo "$result" | jq_field "['reports'][2]['ssid']")"

check "multi AP - 5GHz freq" \
	"5180000" \
	"$(echo "$result" | jq_field "['reports'][1]['freqkhz']")"

# --- test: hidden SSID ---

result=$(cat <<'IW' | parse_iw_scan
BSS ff:ff:ff:ff:ff:ff(on wlan0)
	freq: 2462
	signal: -55.00 dBm
	SSID:
	DS Parameter set: channel 11
IW
)

check "hidden SSID - no ssid key" \
	"False" \
	"$(echo "$result" | jq_field ".get('reports')[0].__contains__('ssid')")"

# --- test: empty input ---

result=$(echo "" | parse_iw_scan)

check "empty input - valid json" \
	"0" \
	"$(echo "$result" | jq_field "['reports'].__len__()")"

# --- test: source metadata ---

check "source name" \
	"test-source" \
	"$(echo "$result" | jq_field "['source_name']")"

check "source uuid" \
	"00000000-0000-0000-0000-000000000000" \
	"$(echo "$result" | jq_field "['source_uuid']")"

# --- test: SSID with quotes ---

result=$(cat <<'IW' | parse_iw_scan
BSS aa:bb:cc:dd:ee:ff(on wlan0)
	freq: 2412
	signal: -50.00 dBm
	SSID: Bob's "Best" WiFi
	DS Parameter set: channel 1
IW
)

check "ssid with quotes - valid json" \
	"1" \
	"$(echo "$result" | jq_field "['reports'].__len__()")"

check "ssid with quotes - value" \
	"Bob's \"Best\" WiFi" \
	"$(echo "$result" | jq_field "['reports'][0]['ssid']")"

# --- test: primary channel fallback ---

result=$(cat <<'IW' | parse_iw_scan
BSS aa:bb:cc:dd:ee:ff(on wlan0)
	freq: 5745
	signal: -60.00 dBm
	SSID: WiFi6E
	HT operation:
		 * primary channel: 149
IW
)

check "primary channel fallback" \
	"149" \
	"$(echo "$result" | jq_field "['reports'][0]['channel']")"

# --- summary ---

if [ "$fail" -eq 0 ]; then
	echo "all tests passed"
else
	echo "some tests FAILED"
	exit 1
fi
