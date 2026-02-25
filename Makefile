SHELL := /bin/bash
OPENWRT := openwrt
KISMET_PKG := kismet-packages
KISMET_SRC := kismet
KISMET_TAG := kismet-2025-09-R1
NPROC := $(shell nproc)

IMAGE_NAME := openwrt-builder
IMAGE_TAG := $(IMAGE_NAME):latest

# if already inside the build container (CI), run in openwrt dir directly.
# otherwise wrap with podman (which bind-mounts openwrt at /build).
IN_CONTAINER := $(wildcard /.dockerenv /run/.containerenv)
ifeq ($(IN_CONTAINER),)
RUN := podman run --rm \
	-v $(CURDIR)/$(OPENWRT):/build:Z \
	-w /build \
	--userns=keep-id \
	$(IMAGE_TAG)
else
RUN :=
endif

# sentinel files
CLONED_OPENWRT := $(OPENWRT)/.git/HEAD
CLONED_KPKG := $(KISMET_PKG)/.git/HEAD
CLONED_KSRC := $(KISMET_SRC)/.git/HEAD
FEEDS_DONE := $(OPENWRT)/.feeds.installed
KISMET_COPIED := $(OPENWRT)/package/kismet-openwrt/.copied
KISMET_PATCHED := $(OPENWRT)/package/kismet-openwrt/.patched
CONFIG := $(OPENWRT)/.config
CONTAINER_BUILT := .container-built
SYSUPGRADE := $(OPENWRT)/bin/targets/mediatek/filogic/openwrt-mediatek-filogic-glinet_gl-x3000-squashfs-sysupgrade.bin

.PHONY: all clone feeds config build build-verbose image menuconfig \
	container diff-kismet clean distclean

all: image

# --- phase 0: build container ---

container: $(CONTAINER_BUILT)
$(CONTAINER_BUILT): Containerfile
	podman build -t $(IMAGE_TAG) -f Containerfile .
	touch $@

# --- phase 1: clone ---

clone: $(CLONED_OPENWRT) $(CLONED_KPKG) $(CLONED_KSRC)

$(CLONED_OPENWRT):
	git clone https://github.com/openwrt/openwrt.git $(OPENWRT)

$(CLONED_KPKG):
	git clone https://github.com/kismetwireless/kismet-packages.git $(KISMET_PKG)

$(CLONED_KSRC):
	git clone https://www.kismetwireless.net/git/kismet.git $(KISMET_SRC)
	cd $(KISMET_SRC) && git checkout $(KISMET_TAG)

# --- phase 2: kismet packages + feeds ---

KISMET_PKGS := kismet kismet-capture-linux-wifi

$(KISMET_COPIED): $(CLONED_KPKG) $(CLONED_OPENWRT)
	mkdir -p $(OPENWRT)/package/kismet-openwrt
	cp $(KISMET_PKG)/openwrt/kismet-openwrt/kismet.mk $(OPENWRT)/package/kismet-openwrt/
	$(foreach pkg,$(KISMET_PKGS),\
		cp -R $(KISMET_PKG)/openwrt/kismet-openwrt/$(pkg) $(OPENWRT)/package/kismet-openwrt/$(pkg);)
	touch $@

$(KISMET_PATCHED): $(KISMET_COPIED)
	# bump version to 2025-09-R1
	sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=2025-09-R1/' \
		$(OPENWRT)/package/kismet-openwrt/kismet.mk
	sed -i 's/^PKG_RELEASE:=.*/PKG_RELEASE:=0/' \
		$(OPENWRT)/package/kismet-openwrt/kismet.mk
	# protobuf is opt-in in 2025-09-R1, drop all protobuf deps
	sed -i '/^PKG_BUILD_DEPENDS:=protobuf-c\/host/d' \
		$(OPENWRT)/package/kismet-openwrt/kismet.mk
	sed -i '/PKG_BUILD_DEPENDS += protobuf\/host/d' \
		$(OPENWRT)/package/kismet-openwrt/kismet/Makefile
	sed -i 's/+protobuf-lite +libprotobuf-c //' \
		$(OPENWRT)/package/kismet-openwrt/kismet/Makefile
	sed -i 's/+protobuf-lite +libprotobuf-c//' \
		$(OPENWRT)/package/kismet-openwrt/kismet-capture-linux-wifi/Makefile
	# drop stale protobuf configure flags (opt-in in 2025-09-R1)
	sed -i '/--with-protoc=/d' \
		$(OPENWRT)/package/kismet-openwrt/kismet.mk
	sed -i '/--enable-protobuflite/d' \
		$(OPENWRT)/package/kismet-openwrt/kismet.mk
	# disable hardware we don't have
	sed -i 's/--disable-wifi-coconut/--disable-libnm \\\n\t--disable-libusb \\\n\t--disable-librtlsdr \\\n\t--disable-ubertooth \\\n\t--disable-mosquitto \\\n\t--disable-wifi-coconut/' \
		$(OPENWRT)/package/kismet-openwrt/kismet.mk
	# update title
	sed -i 's/Kismet 2023/Kismet 2025/' \
		$(OPENWRT)/package/kismet-openwrt/kismet/Makefile
	touch $@

feeds: $(FEEDS_DONE)
# only install feed packages we actually reference in config.seed
FEED_PKGS := gpsd gpsd-clients picocom luci luci-ssl curl wget-ssl \
	htop nano usbutils e2fsprogs block-mount \
	libpcap libpcre2 libsensors libopenssl libnl libcap

$(FEEDS_DONE): $(CLONED_OPENWRT) $(KISMET_PATCHED) $(if $(IN_CONTAINER),,$(CONTAINER_BUILT)) feeds.conf
	cp feeds.conf $(OPENWRT)/feeds.conf
	cd $(OPENWRT) && $(RUN) bash -c './scripts/feeds update -a && ./scripts/feeds install $(FEED_PKGS)'
	touch $@

# --- phase 3: config ---

config: $(CONFIG)
$(CONFIG): $(FEEDS_DONE) config.seed
	cp config.seed $(OPENWRT)/.config
	cd $(OPENWRT) && $(RUN) make defconfig

# --- phase 4: build ---

image: $(SYSUPGRADE)
$(SYSUPGRADE): $(CONFIG)
	cd $(OPENWRT) && $(RUN) bash -c 'make download -j$(NPROC) && make -j$(NPROC)'

build-verbose: $(CONFIG)
	cd $(OPENWRT) && $(RUN) bash -c 'make download -j$(NPROC) && make -j1 V=s 2>&1 | tee build.log'

# --- helpers ---

menuconfig: $(FEEDS_DONE)
	podman run --rm -it \
		-v $(CURDIR)/$(OPENWRT):/build:Z \
		-w /build \
		--userns=keep-id \
		$(IMAGE_TAG) make menuconfig

diff-kismet: $(KISMET_PATCHED)
	@echo "--- kismet.mk ---"
	@cd $(OPENWRT)/package/kismet-openwrt && git diff --no-index /dev/null kismet.mk 2>/dev/null || true
	@echo "--- patched files ---"
	@cd $(OPENWRT)/package/kismet-openwrt && \
	grep -rn 'PKG_VERSION\|DEPENDS\|PKG_BUILD_DEPENDS\|TITLE' kismet.mk kismet/Makefile kismet-capture-linux-wifi/Makefile

clean:
	rm -rf $(OPENWRT)/bin $(OPENWRT)/build_dir $(OPENWRT)/staging_dir
	rm -f $(OPENWRT)/.config $(OPENWRT)/.config.old
	rm -f $(FEEDS_DONE) $(CONFIG)

distclean:
	rm -rf $(OPENWRT) $(KISMET_PKG) $(KISMET_SRC)
	rm -f $(CONTAINER_BUILT) $(KISMET_COPIED) $(KISMET_PATCHED)
	podman rmi $(IMAGE_TAG) 2>/dev/null || true
