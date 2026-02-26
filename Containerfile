FROM docker.io/library/debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential gawk gettext git libncurses-dev python3 \
    rsync unzip wget zstd file \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash builder
WORKDIR /build
