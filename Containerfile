FROM docker.io/library/debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-setuptools \
    rsync swig unzip zlib1g-dev file wget qemu-utils \
    && rm -rf /var/lib/apt/lists/*

# create non-root user for local builds (--userns=keep-id maps host UID)
# CI runs as root with FORCE_UNSAFE_CONFIGURE=1
RUN useradd -m -s /bin/bash builder
WORKDIR /build
