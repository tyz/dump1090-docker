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
        build-essential fakeroot debhelper pkg-config devscripts libncurses5-dev librtlsdr-dev

RUN pwd ; ls -la

COPY ./dump1090-source dump1090-source

WORKDIR /dump1090-source

RUN make BLADERF=no HACKRF=no LIMESDR=no SOAPYSDR=no RTLSDR=yes

###

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

RUN rm /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -ex ; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        librtlsdr0 libncurses6

COPY --from=builder /dump1090-source/dump1090 /dump1090-source/view1090 /dump1090-source/starch-benchmark .
COPY --from=builder /dump1090-source/public_html public_html

COPY ./docker/entrypoint.sh entrypoint.sh
RUN chmod 0755 entrypoint.sh

CMD ["/app/entrypoint.sh"]
