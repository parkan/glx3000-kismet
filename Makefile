SHELL := /bin/bash

OPENWRT_VERSION := 24.10.5
OPENWRT_TARGET  := mediatek-filogic
OPENWRT_ARCH    := aarch64_cortex-a53
OPENWRT_PROFILE := glinet_gl-x3000

KISMET_TAG := kismet-2025-09-R1
NPROC := $(shell nproc)

IMAGE_NAME := openwrt-builder
IMAGE_TAG := $(IMAGE_NAME):latest

RUN := podman run --rm \
	-v $(CURDIR):/build:Z \
	-w /build \
	--userns=keep-id \
	$(IMAGE_TAG)

# download urls
BASE_URL := https://downloads.openwrt.org/releases/$(OPENWRT_VERSION)/targets/mediatek/filogic
SDK_TAR   := openwrt-sdk-$(OPENWRT_VERSION)-$(OPENWRT_TARGET)_gcc-13.3.0_musl.Linux-x86_64.tar.zst
IB_TAR    := openwrt-imagebuilder-$(OPENWRT_VERSION)-$(OPENWRT_TARGET).Linux-x86_64.tar.zst

# local dirs
SDK := $(basename $(basename $(SDK_TAR)))
IB  := $(basename $(basename $(IB_TAR)))
KISMET_PKG := kismet-packages

# sentinel files
CONTAINER_BUILT := .container-built
KISMET_COPIED   := $(SDK)/package/kismet-openwrt/.copied
KISMET_PATCHED  := $(SDK)/package/kismet-openwrt/.patched
KISMET_BUILT    := $(SDK)/.kismet-built

KISMET_PKGS := kismet kismet-capture-linux-wifi

PACKAGES := kismet kismet-capture-linux-wifi \
	gpsd gpsd-clients picocom \
	luci luci-ssl \
	wget-ssl curl htop nano usbutils \
	block-mount kmod-fs-ext4 e2fsprogs kmod-fs-vfat

SYSUPGRADE := $(IB)/bin/targets/mediatek/filogic/openwrt-$(OPENWRT_VERSION)-$(OPENWRT_TARGET)-$(OPENWRT_PROFILE)-squashfs-sysupgrade.bin

.PHONY: all container kismet image clean distclean

all: image

# --- container ---

container: $(CONTAINER_BUILT)
$(CONTAINER_BUILT): Containerfile
	podman build -t $(IMAGE_TAG) -f Containerfile .
	touch $@

# --- download + extract ---

$(SDK_TAR):
	wget -q $(BASE_URL)/$(SDK_TAR)

$(IB_TAR):
	wget -q $(BASE_URL)/$(IB_TAR)

SDK_READY := $(SDK)/.feeds-installed

$(SDK)/.extracted: $(SDK_TAR)
	tar --zstd -xf $(SDK_TAR)
	touch $@

$(SDK_READY): $(SDK)/.extracted $(CONTAINER_BUILT)
	$(RUN) make -C $(SDK) defconfig
	$(RUN) bash -c 'cd $(SDK) && ./scripts/feeds update -a && ./scripts/feeds install -a'
	touch $@

$(IB)/.extracted: $(IB_TAR)
	tar --zstd -xf $(IB_TAR)
	touch $@

# --- kismet packages ---

$(KISMET_PKG)/.git/HEAD:
	git clone https://github.com/kismetwireless/kismet-packages.git $(KISMET_PKG)

$(KISMET_COPIED): $(KISMET_PKG)/.git/HEAD $(SDK_READY)
	mkdir -p $(SDK)/package/kismet-openwrt
	cp $(KISMET_PKG)/openwrt/kismet-openwrt/kismet.mk $(SDK)/package/kismet-openwrt/
	$(foreach pkg,$(KISMET_PKGS),\
		cp -R $(KISMET_PKG)/openwrt/kismet-openwrt/$(pkg) $(SDK)/package/kismet-openwrt/$(pkg);)
	touch $@

$(KISMET_PATCHED): $(KISMET_COPIED)
	# bump version; pin git tag explicitly
	sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=2025.09.1/' \
		$(SDK)/package/kismet-openwrt/kismet.mk
	sed -i 's/^PKG_RELEASE:=.*/PKG_RELEASE:=0/' \
		$(SDK)/package/kismet-openwrt/kismet.mk
	sed -i 's/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$(KISMET_TAG)/' \
		$(SDK)/package/kismet-openwrt/kismet.mk
	# protobuf is opt-in in 2025-09-R1, drop all protobuf deps
	sed -i '/^PKG_BUILD_DEPENDS:=protobuf-c\/host/d' \
		$(SDK)/package/kismet-openwrt/kismet.mk
	sed -i '/PKG_BUILD_DEPENDS += protobuf\/host/d' \
		$(SDK)/package/kismet-openwrt/kismet/Makefile
	sed -i 's/+protobuf-lite +libprotobuf-c //' \
		$(SDK)/package/kismet-openwrt/kismet/Makefile
	sed -i 's/+protobuf-lite +libprotobuf-c//' \
		$(SDK)/package/kismet-openwrt/kismet-capture-linux-wifi/Makefile
	# drop stale protobuf configure flags
	sed -i '/--with-protoc=/d' \
		$(SDK)/package/kismet-openwrt/kismet.mk
	sed -i '/--enable-protobuflite/d' \
		$(SDK)/package/kismet-openwrt/kismet.mk
	# disable hardware we don't have
	sed -i 's/--disable-wifi-coconut/--disable-libnm \\\n\t--disable-libusb \\\n\t--disable-librtlsdr \\\n\t--disable-ubertooth \\\n\t--disable-mosquitto \\\n\t--disable-wifi-coconut/' \
		$(SDK)/package/kismet-openwrt/kismet.mk
	# update title
	sed -i 's/Kismet 2023/Kismet 2025/' \
		$(SDK)/package/kismet-openwrt/kismet/Makefile
	touch $@

# --- compile kismet ---

$(KISMET_BUILT): $(KISMET_PATCHED)
	$(RUN) make -C $(SDK) package/kismet-openwrt/kismet/compile V=s -j1
	$(RUN) make -C $(SDK) package/kismet-openwrt/kismet-capture-linux-wifi/compile V=s -j1
	touch $@

kismet: $(KISMET_BUILT)

# --- assemble image ---

$(SYSUPGRADE): $(KISMET_BUILT) $(IB)/.extracted
	cp $(SDK)/bin/packages/$(OPENWRT_ARCH)/base/kismet*.ipk $(IB)/packages/
	$(RUN) make -C $(IB) image \
		PROFILE="$(OPENWRT_PROFILE)" \
		PACKAGES="$(PACKAGES)" \
		$(if $(wildcard files),FILES="$(CURDIR)/files/")

image: $(SYSUPGRADE)

# --- helpers ---

clean:
	rm -rf $(SDK)/build_dir $(SDK)/bin $(SDK)/staging_dir/target-*
	rm -rf $(IB)/bin $(IB)/build_dir
	rm -f $(KISMET_BUILT) $(KISMET_PATCHED) $(KISMET_COPIED)

distclean:
	rm -rf $(SDK) $(IB) $(KISMET_PKG)
	rm -f $(SDK_TAR) $(IB_TAR) $(CONTAINER_BUILT)
	podman rmi $(IMAGE_TAG) 2>/dev/null || true
