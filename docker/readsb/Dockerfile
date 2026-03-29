# syntax=docker/dockerfile:1

FROM debian:bookworm AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN rm /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -ex ; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        git build-essential pkg-config cmake libncurses5-dev zlib1g-dev libzstd-dev ca-certificates libusb-1.0-0-dev


RUN git clone --depth 1 https://github.com/rtlsdrblog/rtl-sdr-blog.git /tmp/rtl-sdr
WORKDIR /tmp/rtl-sdr/build
RUN cmake ../ -DINSTALL_UDEV_RULES=ON && \
    make -j$(nproc) && \
    make install && \
    ldconfig

WORKDIR /tmp/readsb

RUN git clone --depth 1 https://github.com/wiedehopf/readsb.git .

RUN make RTLSDR=yes

###

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN rm /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -ex ; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libncurses6 zlib1g libusb-1.0-0 ca-certificates git

WORKDIR /app

COPY --from=builder /usr/local/lib/librtlsdr.so.*.* /usr/local/lib
COPY --from=builder /usr/local/bin/rtl_* /usr/local/bin
COPY --from=builder /tmp/readsb/readsb .
COPY entrypoint.sh .

RUN ldconfig && \
    chmod 755 entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
