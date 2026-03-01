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
        git build-essential pkg-config librtlsdr-dev libncurses5-dev zlib1g-dev libzstd-dev ca-certificates

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
        librtlsdr0 libncurses6 zlib1g

WORKDIR /app

COPY --from=builder /tmp/readsb/readsb .

COPY ./docker/entrypoint.sh entrypoint.sh

RUN chmod 0755 entrypoint.sh

CMD ["/app/entrypoint.sh"]
