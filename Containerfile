FROM docker.io/library/ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-distutils python3-setuptools \
    rsync swig unzip zlib1g-dev file wget qemu-utils \
    && rm -rf /var/lib/apt/lists/*

# openwrt build must not run as root
RUN useradd -m -s /bin/bash builder
USER builder
WORKDIR /build
