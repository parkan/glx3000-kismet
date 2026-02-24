# GL-X3000 Kismet Survey Image: Build Plan for Claude Code

## Objective

Build a custom OpenWrt image for the GL-iNet GL-X3000 (Spitz AX) that provides:

1. **Pre-event WiFi site survey** via Kismet scanning mode (no monitor mode required)
2. **During-event WiFi monitoring** via Kismet in monitor mode (client visibility, channel utilization, rogue AP detection)
3. **GPS integration** via the onboard Quectel RM520N-GL GNSS receiver
4. **Web UI** accessible from phone/laptop for real-time visualization during walkabouts

Target release: **Kismet 2025-09-R1** (Python-free, reduced dependencies).
Target platform: **mediatek/filogic**, profile **glinet_gl-x3000**.

---

## Phase 0: Host Prerequisites

```bash
# Ubuntu/Debian build host
sudo apt update
sudo apt install -y \
  build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses-dev libssl-dev python3-distutils python3-setuptools \
  rsync swig unzip zlib1g-dev file wget qemu-utils

# Verify disk space: need ~15GB minimum for full build
df -h .
```

---

## Phase 1: Clone Repos

```bash
mkdir -p ~/openwrt-kismet-build && cd ~/openwrt-kismet-build

# 1. OpenWrt source (use latest stable branch or master snapshot)
git clone https://github.com/openwrt/openwrt.git
cd openwrt
# Pin to a known-good snapshot tag if available, otherwise master is fine
# git checkout v23.05.5  # or stay on master for GL-X3000 support (merged 2024)

# 2. Kismet packaging scripts (separate repo from the dead openwrt-packages fork)
cd ~/openwrt-kismet-build
git clone https://github.com/kismetwireless/kismet-packages.git

# 3. Kismet source (for reference / version pinning)
git clone https://www.kismetwireless.net/git/kismet.git
cd kismet
git checkout kismet-2025-09-R1
KISMET_VERSION=$(git describe --tags)
echo "Building against Kismet version: $KISMET_VERSION"
cd ~/openwrt-kismet-build
```

---

## Phase 2: Prepare OpenWrt Feeds + Kismet Packages

```bash
cd ~/openwrt-kismet-build/openwrt

# 2a. Update standard feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 2b. Copy Kismet OpenWrt package definitions into the build tree
cp -R ../kismet-packages/openwrt/kismet-openwrt packages/

# 2c. CRITICAL: Check if the Kismet Makefiles target 2025-09-R1.
#     If PKG_VERSION still says 2023-07-R1 or similar, update it.
#     The Makefile is at: packages/kismet-openwrt/kismet/Makefile
#     and individual capture tools under packages/kismet-openwrt/kismet-capture-*/Makefile
#
#     Fields to update in the main kismet Makefile:
#       PKG_VERSION:=2025-09-R1
#       PKG_SOURCE_VERSION:=kismet-2025-09-R1   (git tag)
#
#     If the Makefiles are already current, skip this.

grep -r "PKG_VERSION" packages/kismet-openwrt/*/Makefile | head -20
# Review output. If outdated, patch:

# Example patch (adjust paths to actual Makefile locations):
# sed -i 's/PKG_VERSION:=.*/PKG_VERSION:=2025-09-R1/' packages/kismet-openwrt/kismet/Makefile
# sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=kismet-2025-09-R1/' packages/kismet-openwrt/kismet/Makefile
```

**Decision point:** If the Kismet OpenWrt Makefiles have not been updated for 2025-09-R1 and the build breaks, fall back to the last known-good version (2023-07-R1) and note it. The 2025-09-R1 gains (no Python, less RAM) are significant but not blocking.

---

## Phase 3: Configure the Image

```bash
cd ~/openwrt-kismet-build/openwrt

make menuconfig
```

### menuconfig selections

#### Target / Profile
```
Target System        → MediaTek Ralink ARM
Subtarget            → Filogic 8x0 (MT798x)
Target Profile       → GL.iNet GL-X3000
```

#### Kismet packages (under Network)
Navigate to `Network` → scroll to `kismet`. Select:

```
<M> kismet                          # Full server (web UI, device tracking, logging)
<M> kismet-capture-linux-wifi       # WiFi capture (monitor mode + scanning mode)
```

Do NOT select unless needed:
```
[ ] kismet-capture-linux-bluetooth  # Skip unless BT monitoring desired
[ ] kismet-capture-sdr-rtl433       # Skip unless SDR hardware present
[ ] kismet-tools                    # Log manipulation tools; build on host instead
```

#### Wireless / Drivers (CRITICAL for monitor mode)
```
Kernel modules → Wireless Drivers:
  <*> kmod-mt76-core
  <*> kmod-mt7915e          # This is the driver for MT7981's WiFi (mt7976 radios)
  <*> kmod-mac80211          # Required for monitor mode VIF creation
```

Verify that `kmod-cfg80211` is pulled in as a dependency. It should be automatic.

#### GPS / Modem Support
```
Utilities:
  <*> gpsd                   # GPS daemon
  <*> gpsd-clients           # gpspipe, cgps for testing

Network:
  <*> modem-manager          # For Quectel RM520N-GL AT command interface
  # OR if modem-manager is too heavy:
  <*> qmi-utils              # Lighter alternative for AT commands
  <*> picocom                # Serial terminal for manual AT debugging
```

#### Networking / Convenience
```
LuCI:
  <*> luci                   # Web admin UI (optional but useful for AP config)
  <*> luci-ssl               # HTTPS for LuCI

Network:
  <*> wget-ssl               # For fetching packages post-install if needed
  <*> curl

Utilities:
  <*> htop                   # Resource monitoring on the device
  <*> nano                   # In-field config editing
  <*> usbutils               # lsusb for debugging modem
```

#### Storage (the X3000 has 8GB eMMC + microSD)
```
Base system:
  <*> block-mount
  <*> kmod-fs-ext4
  <*> e2fsprogs

Kernel modules → Filesystems:
  <*> kmod-fs-vfat           # For microSD
```

Save and exit.

---

## Phase 4: Build

```bash
cd ~/openwrt-kismet-build/openwrt

# Download sources first (can retry on failure)
make download -j$(nproc)

# Full build. First build takes 1-3 hours depending on hardware.
# Use -j1 V=s on first build to catch errors clearly.
make -j1 V=s 2>&1 | tee build.log

# Subsequent builds (after fixing issues):
# make -j$(nproc)
```

### Known build issues to watch for

1. **protobuf-c host tool**: The Kismet Makefile may expect `protoc-c` in the staging dir. If build fails with `protoc-c not found`:
   ```bash
   sudo apt install protobuf-c-compiler
   # Then symlink if needed:
   ln -s /usr/bin/protoc-c staging_dir/target-*/host/bin/protoc-c
   ```
   Note: Kismet 2025-09-R1 made protobufs optional. If building that version, the Makefile may not need this at all.

2. **libwebsockets**: Required for remote capture websocket support. Should be in the OpenWrt feeds. If missing:
   ```bash
   ./scripts/feeds install libwebsockets
   ```

3. **eeprom/calibration data**: The MT7981 WiFi needs calibration data. Vanilla OpenWrt should include it for the GL-X3000 profile. If WiFi fails to probe with `eeprom load fail`, the DTS or firmware blob is missing — check the build log for `mt7981_eeprom_mt7976_dbdc.bin`.

### Output location

```bash
ls -la bin/targets/mediatek/filogic/openwrt-mediatek-filogic-glinet_gl-x3000-squashfs-sysupgrade.bin
```

---

## Phase 5: Flash the Image

### Backup current firmware first

On the GL-X3000 running stock GL-iNet firmware:
```bash
# SSH into stock firmware
ssh root@192.168.8.1

# Dump current firmware for restoration
dd if=/dev/mmcblk0 of=/tmp/mmcblk0-full-backup.img bs=1M
# Copy off device via SCP
```

### Flash via U-Boot rescue

1. Power off the router
2. Press and hold the **Reset** button
3. Power on while holding Reset
4. Wait for the **Internet LED to blink 5 times**, then release Reset
5. Connect laptop to LAN port, set static IP `192.168.1.2/24`
6. Navigate to `http://192.168.1.1`
7. Upload `openwrt-mediatek-filogic-glinet_gl-x3000-squashfs-sysupgrade.bin`
8. Wait for reboot (~2-3 minutes)

---

## Phase 6: Post-Flash Configuration

### 6a. Verify WiFi and Monitor Mode

```bash
ssh root@192.168.1.1

# Check WiFi hardware detected
iw phy

# Check monitor mode support on BOTH radios
iw phy phy0 info | grep -A5 "Supported interface modes"
iw phy phy1 info | grep -A5 "Supported interface modes"

# Expected output should include "monitor" in the list.
# If monitor mode is NOT listed, flag this — scanning mode fallback is needed
# for during-event use, which limits client visibility.
```

### 6b. Configure GNSS

```bash
# Find the modem's serial ports
ls /dev/ttyUSB*
# Typical: ttyUSB0 (DM), ttyUSB1 (NMEA), ttyUSB2 (AT), ttyUSB3 (AT)
# May also appear as /dev/cdc-wdm0 for QMI

# Enable GNSS via AT commands
# Use picocom or direct echo to the AT port:
picocom -b 115200 /dev/ttyUSB2
# Then type:
#   AT+QGPS=1
#   AT+QGPSCFG="outport","usbnmea"
#   AT+QGPSCFG="autogps",1
#   AT+QGPSCFG="gnssconfig",1
# Ctrl-A, Ctrl-X to exit picocom

# Verify NMEA output
cat /dev/ttyUSB1
# Should see $GPGGA, $GPRMC etc. sentences after fix acquired (may take minutes)

# Configure gpsd
cat > /etc/config/gpsd << 'EOF'
config gpsd 'core'
    option enabled '1'
    option device '/dev/ttyUSB1'
    option port '2947'
    option listen_globally '1'
EOF

/etc/init.d/gpsd enable
/etc/init.d/gpsd start

# Test
cgps -s
# Should show lat/lon after satellite fix
```

**If GNSS doesn't work on vanilla OpenWrt** (common: serial port enumeration differs), create a startup script to probe for the correct port:

```bash
cat > /etc/init.d/gnss-setup << 'INITEOF'
#!/bin/sh /etc/rc.common
START=80

start() {
    # Find AT port (try common locations)
    for port in /dev/ttyUSB2 /dev/ttyUSB3 /dev/ttyUSB0; do
        if [ -c "$port" ]; then
            echo -e "AT+QGPS=1\r" > "$port"
            sleep 1
            echo -e 'AT+QGPSCFG="outport","usbnmea"\r' > "$port"
            echo -e 'AT+QGPSCFG="autogps",1\r' > "$port"
            logger "GNSS enabled via $port"
            break
        fi
    done
}
INITEOF
chmod +x /etc/init.d/gnss-setup
/etc/init.d/gnss-setup enable
```

**Fallback: USB GPS dongle.** If the Quectel GNSS is uncooperative, plug a VK-162 or similar into the USB-A port. It will appear as `/dev/ttyACM0` and work with gpsd out of the box.

### 6c. Configure Kismet

```bash
# Create site-specific override config
mkdir -p /etc/kismet
cat > /etc/kismet/kismet_site.conf << 'EOF'
# ============================================================
# GL-X3000 Kismet Site Config
# ============================================================

# --- Server ---
# Listen on all interfaces so phone/laptop can connect
httpd_bind_address=0.0.0.0
httpd_port=2501

# --- GPS ---
gps=gpsd:host=localhost,port=2947

# --- Sources ---
# Uncomment ONE of the following blocks depending on mode:

# === MODE A: SURVEY (pre-event, scanning mode, no monitor needed) ===
# This uses iw scan under the hood. Safe, works without monitor mode.
# Driven externally via scan report API — see survey-walk.sh script below.
# No source= line needed; scanning mode creates datasources dynamically.

# === MODE B: MONITOR (during event, full client visibility) ===
# Requires monitor mode confirmed working (Phase 6a).
# Uncomment and adjust interface names:
# source=wlan0:name=Survey5G,channel_hop=true,ht_channels=true,vht_channels=true
# source=wlan1:name=Survey2G,channel_hop=true

# --- Logging ---
log_prefix=/tmp/kismet
log_types=kismet

# --- Memory / Performance (constrained device) ---
# Disable packet retention in memory (we log to disk)
kis_log_packets=true
# Limit tracked devices to reduce RAM (increase if needed)
tracker_device_timeout=600
# Disable unused phy handlers
dot11_fingerprint_devices=false

# --- Alerts ---
alertbacklog=50
EOF

# Set admin password (REQUIRED on first run)
cat > /etc/kismet/kismet_httpd.conf << 'EOF'
httpd_username=admin
httpd_password=CHANGEME
EOF
chmod 600 /etc/kismet/kismet_httpd.conf
```

### 6d. Create Survey Walk Script (Scanning Mode — Pre-Event)

This script runs on the GL-X3000 and submits scan reports to the local Kismet server via the scanning mode REST API. No monitor mode required.

```bash
cat > /usr/bin/survey-walk.sh << 'SCRIPT'
#!/bin/sh
# survey-walk.sh — feed iw scan results to Kismet scanning mode API
# Usage: start Kismet first, then run this script.

KISMET_URL="http://localhost:2501"
KISMET_USER="admin"
KISMET_PASS="CHANGEME"
IFACE="${1:-wlan0}"
UUID="11111111-1111-1111-1111-111111111111"
NAME="GL-X3000-Survey"

# Get API cookie
COOKIE=$(mktemp)
curl -s -c "$COOKIE" -b "$COOKIE" \
  -d "username=$KISMET_USER&password=$KISMET_PASS" \
  "$KISMET_URL/session/check_session" > /dev/null

while true; do
    TIMESTAMP=$(date +%s)
    
    # Get GPS from gpsd
    GPSJSON=$(gpspipe -w -n 5 2>/dev/null | grep -m1 '"class":"TPV"')
    LAT=$(echo "$GPSJSON" | jsonfilter -e '$.lat' 2>/dev/null || echo "0")
    LON=$(echo "$GPSJSON" | jsonfilter -e '$.lon' 2>/dev/null || echo "0")
    ALT=$(echo "$GPSJSON" | jsonfilter -e '$.alt' 2>/dev/null || echo "0")
    
    # Scan
    SCAN=$(iw dev "$IFACE" scan 2>/dev/null)
    
    # Parse scan results into JSON reports
    REPORTS="["
    FIRST=1
    echo "$SCAN" | awk '
    /^BSS / { if (bss) print bss"|"freq"|"signal"|"ssid; bss=$2; freq=""; signal=""; ssid="" }
    /freq:/ { freq=$2 }
    /signal:/ { signal=$2 }
    /SSID:/ { $1=""; ssid=substr($0,2) }
    END { if (bss) print bss"|"freq"|"signal"|"ssid }
    ' | while IFS='|' read -r bss freq signal ssid; do
        bss=$(echo "$bss" | tr -d '()')
        signal_i=$(echo "$signal" | cut -d. -f1)
        [ -z "$signal_i" ] && signal_i=-100
        
        if [ "$FIRST" = 1 ]; then
            FIRST=0
        else
            printf ','
        fi
        
        cat << ENTRY
{"timestamp": $TIMESTAMP, "lat": $LAT, "lon": $LON, "alt": $ALT, "bssid": "$bss", "ssid": "$ssid", "freq": $freq, "signal": $signal_i}
ENTRY
    done > /tmp/scan_reports.json
    
    REPORTS=$(cat /tmp/scan_reports.json | tr '\n' ',' | sed 's/,$//')
    
    # Submit to Kismet
    curl -s -b "$COOKIE" \
      -H "Content-Type: application/json" \
      -d "{\"datasource\": {\"uuid\": \"$UUID\", \"name\": \"$NAME\"}, \"reports\": [$REPORTS]}" \
      "$KISMET_URL/phy/WIFI/scan/scan_report.json" > /dev/null
    
    sleep 3
done

rm -f "$COOKIE"
SCRIPT
chmod +x /usr/bin/survey-walk.sh
```

### 6e. Create Monitor Mode Startup Script (During Event)

```bash
cat > /usr/bin/kismet-monitor.sh << 'SCRIPT'
#!/bin/sh
# kismet-monitor.sh — start Kismet in full monitor mode for event-day use
# Requires monitor mode support confirmed in Phase 6a.

# Identify interfaces
PHY0_IFACE=$(iw dev | awk '/Interface/{print $2}' | head -1)
PHY1_IFACE=$(iw dev | awk '/Interface/{print $2}' | tail -1)

echo "Starting Kismet with monitor mode on $PHY0_IFACE and $PHY1_IFACE"

# Update kismet_site.conf to use monitor sources
cat > /etc/kismet/kismet_site.conf << EOF
httpd_bind_address=0.0.0.0
httpd_port=2501
gps=gpsd:host=localhost,port=2947
source=${PHY0_IFACE}:name=5GHz,channel_hop=true,ht_channels=true,vht_channels=true
source=${PHY1_IFACE}:name=2GHz,channel_hop=true
log_prefix=/tmp/kismet
log_types=kismet
tracker_device_timeout=600
EOF

# Start Kismet (it handles monitor VIF creation itself)
kismet --no-ncurses --daemonize
echo "Kismet running. UI at http://$(uci get network.lan.ipaddr):2501"
SCRIPT
chmod +x /usr/bin/kismet-monitor.sh
```

---

## Phase 7: UI Access

### Primary: Kismet Web UI

Kismet serves a full web UI on port 2501. Access from any device on the same network:

```
http://<gl-x3000-ip>:2501
```

The 2025-09-R1 UI includes:
- Device list with sortable/filterable columns
- Channel coverage visualization (current + historical)
- Per-AP signal strength, encryption, client count
- GPS map overlay (if GPS is active)
- Data source management (lock channels, adjust hop rate)
- Alert log (rogue APs, deauth floods, etc.)
- Dark mode

**For phone use during walkabouts:** The Kismet UI is responsive and works in mobile browsers. Bookmark it. The GL-X3000 WiFi can serve as an AP while one radio is in monitor mode (mt76 supports concurrent AP + monitor VIFs on separate radios).

### Operational Workflow

```
┌──────────────────────────────────────────────────────────┐
│                    PRE-EVENT SURVEY                       │
│                                                          │
│  1. Boot GL-X3000 with custom image                      │
│  2. Wait for GPS fix (cgps -s to verify)                 │
│  3. Connect phone to GL-X3000's AP                       │
│  4. SSH in and start Kismet:                             │
│       kismet --no-ncurses --daemonize                    │
│  5. Start survey scanner:                                │
│       survey-walk.sh wlan0                               │
│  6. Walk the property with device on back                │
│  7. Monitor http://<ip>:2501 on phone for live view      │
│  8. Stop. Copy /tmp/kismet/*.kismet log to laptop        │
│  9. Post-process: generate heatmap from kismetdb         │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                    EVENT DAY MONITORING                   │
│                                                          │
│  1. Place GL-X3000 in central location with power        │
│  2. SSH in, run: kismet-monitor.sh                       │
│  3. Access UI from laptop: http://<ip>:2501              │
│  4. Monitor:                                             │
│     - Channel utilization per band                       │
│     - Client counts per AP                               │
│     - Rogue AP detection (attendee hotspots)             │
│     - Signal strength anomalies                          │
│  5. Use Kismet UI "Data Sources" to lock specific        │
│     channels if investigating a problem area             │
│  6. Adjust Ubiquiti AP channels/power via UniFi          │
│     controller based on Kismet observations              │
│                                                          │
│  For roaming checks: swap to battery, walk problem       │
│  areas, compare Kismet device visibility                 │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Post-Processing (on laptop, not on the GL-X3000)

```bash
# Install kismet log tools
pip install kismet-db

# Export devices with GPS to KML for Google Earth overlay
python3 -c "
import kismetdb
db = kismetdb.Devices('survey.kismet')
# ... extract BSSID, signal, lat, lon, generate KML
"

# Or use sqlite3 directly (kismetdb is standard sqlite3)
sqlite3 survey.kismet "
  SELECT 
    json_extract(device, '$.kismet.device.base.macaddr'),
    json_extract(device, '$.kismet.device.base.signal.min_signal_dbm'),
    json_extract(snapshots.lat),
    json_extract(snapshots.lon)
  FROM devices
  JOIN ...
"

# For heatmap: extract signal readings per location, plot with matplotlib
# over a satellite image or site plan of the property
```

---

## Appendix A: Fallback — If Monitor Mode Doesn't Work on mt76/MT7981

If `iw phy phyX info` does NOT list monitor mode, or Kismet fails to create a monitor VIF:

1. **Pre-event survey** is unaffected — scanning mode works without monitor.
2. **During-event monitoring** loses client visibility but retains AP-level data via scanning mode.
3. **Mitigation**: Use the UniFi controller for client-level stats (it already tracks client counts, airtime, signal per AP). Use Kismet for the RF-level view it adds: channel utilization, rogue AP detection, interference sources.
4. **Alternative**: Add an external USB WiFi adapter with known monitor mode support (e.g., Alfa AWUS036ACH with RTL8812AU — needs out-of-tree driver, complicates the build). Only pursue this if monitor mode on the onboard radios is confirmed broken.

## Appendix B: Concurrent AP + Monitor

The MT7981 has two radios (2.4 GHz + 5 GHz) via the MT7976C. mt76 supports multiple VIFs per radio. The intended configuration:

- **Radio 0 (5 GHz):** Monitor mode VIF for Kismet + AP VIF for management access (phone connects here)
- **Radio 1 (2.4 GHz):** Monitor mode VIF for Kismet (or disabled per event policy)

Kismet handles creating the monitor VIF automatically. The AP VIF should remain functional. Test this explicitly — some mt76 firmware builds don't handle concurrent AP + monitor gracefully. If it fails, dedicate one radio to monitor and the other to AP:

- **Radio 0 (5 GHz):** AP only (management access)
- **Radio 1 (2.4 GHz):** Monitor only (Kismet capture)

This sacrifices 5 GHz monitoring but keeps you connected.

## Appendix C: Channel Plan Notes for Event Day

When adjusting Ubiquiti AP channels based on Kismet data:

| Band | Non-overlapping channels | Width | Notes |
|------|------------------------|-------|-------|
| 2.4 GHz | 1, 6, 11 | 20 MHz only | Disable on most APs per plan |
| 5 GHz (UNII-1) | 36, 40, 44, 48 | 20/40 MHz | No DFS, always available |
| 5 GHz (UNII-2) | 52-64 | 20/40 MHz | DFS required, may blank on radar |
| 5 GHz (UNII-2e) | 100-144 | 20/40 MHz | DFS, most channels here |
| 5 GHz (UNII-3) | 149, 153, 157, 161, 165 | 20/40 MHz | No DFS |

At 500 people with 15-25 APs, use **40 MHz channel width** maximum on 5 GHz to maximize non-overlapping channel availability. Set TX power to medium/low on dense clusters — lower power = smaller cells = less co-channel interference = more spatial reuse.

## Appendix D: File Manifest

After a successful build, these files matter:

```
bin/targets/mediatek/filogic/
  openwrt-mediatek-filogic-glinet_gl-x3000-squashfs-sysupgrade.bin  ← flash this
  openwrt-mediatek-filogic-glinet_gl-x3000-initramfs-kernel.bin     ← test boot without flashing
  sha256sums
```

Use the **initramfs** image first for testing — it boots from RAM without touching eMMC, so your stock firmware is preserved. Once everything works, flash the sysupgrade image.
