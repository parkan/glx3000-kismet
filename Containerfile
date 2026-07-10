FROM docker.io/library/debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential gawk gettext git libncurses-dev python3 python3-setuptools \
    rsync swig unzip wget zstd file \
    && rm -rf /var/lib/apt/lists/*

# force IPv4 for wget: IPv6 to downloads.openwrt.org is a black hole in the
# rootless container, and opkg's wget retries it (default 20 tries) with no
# fast failure -- that hangs `make image` for minutes at "Building package
# index". inet4_only makes every wget (including opkg's) skip IPv6 entirely.
RUN printf 'inet4_only = on\n' >> /etc/wgetrc

RUN useradd -m -s /bin/bash builder
WORKDIR /build
