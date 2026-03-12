# glx3000-kismet

Custom OpenWrt 24.10.5 firmware for the GL-iNet GL-X3000 with
[Kismet](https://www.kismetwireless.net/) wireless survey tools.

Only Kismet is compiled from source. Everything else comes from
pre-built OpenWrt packages. The build uses the OpenWrt SDK for
cross-compilation and the Image Builder to assemble the final
firmware.

## What's included

On top of the default GL-X3000 OpenWrt image:

- kismet + kismet-capture-linux-wifi (2025-09-R1)
- gpsd, gpsd-clients, picocom
- luci + luci-ssl
- wget-ssl, curl, htop, nano, usbutils
- ext4 and vfat filesystem support

## Requirements

- podman (or docker with minor Makefile edits)
- make
- ~10 GB disk space (SDK + Image Builder + build artifacts)

## Building

```
make image
```

This handles everything: builds the container, downloads the SDK and
Image Builder, fetches feed dependencies, compiles Kismet, and
assembles the firmware image.

The output lands at:

```
openwrt-imagebuilder-*/bin/targets/mediatek/filogic/openwrt-24.10.5-mediatek-filogic-glinet_gl-x3000-squashfs-sysupgrade.bin
```

### Other targets

```
make container   # build the podman container only
make kismet      # compile kismet packages only
make clean       # remove build outputs (preserves SDK state)
make distclean   # remove everything, start from scratch
```

## Installing

### Option 1: sysupgrade (permanent)

This replaces the existing firmware. Settings are not preserved since
this is a different OpenWrt configuration.

**Via LuCI (web UI):**

1. Open `http://192.168.8.1` (default GL-iNet address)
2. Go to System -> Backup / Flash Firmware
3. Uncheck "Keep settings and retain the current configuration"
4. Upload the `*-sysupgrade.bin` file and confirm

**Via command line (from the router):**

```
scp openwrt-imagebuilder-*/bin/targets/mediatek/filogic/*-sysupgrade.bin root@192.168.8.1:/tmp/
ssh root@192.168.8.1
sysupgrade -n /tmp/*-sysupgrade.bin
```

The `-n` flag discards existing settings, which is what you want for
a clean install of a different firmware build.

### Option 2: initramfs (temporary boot)

Boot the image from RAM without touching flash. Good for testing --
everything resets on reboot.

1. Connect to the router via ethernet
2. Power off the router
3. Hold the reset button, power on, and keep holding until the power
   LED flashes rapidly (bootloader recovery mode)
4. Set your IP to `192.168.1.2/24` (the bootloader listens on `192.168.1.1`)
5. Upload the initramfs image via TFTP or the bootloader's web recovery:

**Via web recovery:**

Open `http://192.168.1.1` in a browser and upload the
`*-initramfs-kernel.bin` file.

**Via TFTP:**

```
tftp 192.168.1.1
binary
put openwrt-imagebuilder-*/bin/targets/mediatek/filogic/*-initramfs-kernel.bin
```

The router boots into the custom image. Nothing is written to flash.
Power cycle to return to the original firmware.

### After install

The router will be at `192.168.1.1` with OpenWrt defaults (no
password set). SSH in and set a root password:

```
ssh root@192.168.1.1
passwd
```

## Scanning

The GL-X3000 has two radios: `phy0` (2.4 GHz, mt76) and `phy1`
(5 GHz, mt76). Both support monitor mode. You can dedicate one or
both to scanning while keeping the other for management access.

Access the Kismet web UI at `http://<router-ip>:2501` after starting.

### Monitor mode (promiscuous)

Full passive capture -- sees all frames including those destined for
other stations. Required for complete survey coverage.

```sh
# take down any managed interfaces on the radio you want to use
ip link set wlan1 down
iw dev wlan1 del

# create a monitor interface
iw phy phy1 interface add mon0 type monitor
ip link set mon0 up

# start kismet with the monitor source
kismet -c mon0
```

To scan both radios:

```sh
ip link set wlan0 down
iw dev wlan0 del
iw phy phy0 interface add mon1 type monitor
ip link set mon1 up

kismet -c mon0 -c mon1
```

This tears down the WiFi AP, so you need wired ethernet or a
separate management interface to reach the router.

To restore normal operation afterward:

```sh
ip link set mon0 down
iw dev mon0 del
wifi up
```

### Associated mode (non-promiscuous)

Kismet scans using the managed (AP/client) interface without entering
monitor mode. Sees only beacons, probe responses, and frames the
radio would normally receive. Less complete than monitor mode, but
the WiFi AP stays up -- clients stay connected and you can manage
the router over WiFi.

```sh
kismet -c wlan1:type=linuxwifi,vif=managed
```

Or both radios:

```sh
kismet -c wlan0:type=linuxwifi,vif=managed -c wlan1:type=linuxwifi,vif=managed
```

Kismet will trigger periodic channel hops using the existing
interface. Clients may see brief interruptions during hops but
generally stay associated.

### Adding GPS

If a USB GPS is connected (shows up as `/dev/ttyUSB*` or
`/dev/ttyACM*`):

```sh
gpsd /dev/ttyUSB0
kismet -c mon0 --override gps=gpsd:host=localhost,port=2947
```

Kismet logs location data alongside wireless observations, producing
wardriving-style output.
