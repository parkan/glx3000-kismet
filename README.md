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

Kismet is ready to run:

```
kismet
```

Access the Kismet web UI at `http://192.168.1.1:2501`.
