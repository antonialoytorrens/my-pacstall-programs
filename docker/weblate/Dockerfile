# syntax=docker/dockerfile:1
# Platform is set by CI/Makefile via --platform (pacstall cannot cross-build).
FROM debian:trixie AS builder

ARG PACSTALL_VERSION=6.4.2
ARG PACSTALL_REVISION=pacstall1
ARG SPDX_LICENSES_VERSION=3.27.0
ARG SPDX_LICENSES_REVISION=+ds-1
ENV DEBIAN_FRONTEND=noninteractive
# Same on all arches (no-op outside armhf); keeps builds uniform with the pacscript.
ENV CFLAGS_armv7_unknown_linux_gnueabihf="-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard"

RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    ca-certificates sudo curl \
    python3.13 python3.13-venv python3.13-dev build-essential pkg-config cmake \
    libpq-dev libxml2-dev libxslt1-dev libffi-dev \
    libcairo2-dev libgirepository-2.0-dev gir1.2-girepository-2.0-dev \
    gir1.2-pango-1.0 gir1.2-harfbuzz-0.0 gir1.2-rsvg-2.0 \
    libacl1-dev liblz4-dev libzstd-dev libjpeg-dev zlib1g-dev \
    tesseract-ocr libtesseract-dev libleptonica-dev \
    git tzdata \
  && echo "deb http://deb.debian.org/debian trixie-backports main" \
    > /etc/apt/sources.list.d/backports.list \
  && apt-get update -qq \
  && apt-get install -y -qq -t trixie-backports rustc cargo

ADD https://github.com/pacstall/pacstall/releases/download/${PACSTALL_VERSION}/pacstall_${PACSTALL_VERSION}-${PACSTALL_REVISION}_all.deb \
  /var/cache/apt/archives/pacstall_${PACSTALL_VERSION}-${PACSTALL_REVISION}_all.deb
ADD https://ftp.debian.org/debian/pool/main/s/spdx-licenses/spdx-licenses_${SPDX_LICENSES_VERSION}${SPDX_LICENSES_REVISION}_all.deb \
  /var/cache/apt/archives/spdx-licenses_${SPDX_LICENSES_VERSION}${SPDX_LICENSES_REVISION}_all.deb

RUN apt-get install -y -qq -f \
    /var/cache/apt/archives/pacstall_${PACSTALL_VERSION}-${PACSTALL_REVISION}_all.deb \
    /var/cache/apt/archives/spdx-licenses_${SPDX_LICENSES_VERSION}${SPDX_LICENSES_REVISION}_all.deb

WORKDIR /build
COPY packagelist srclist /build/
COPY packages/ /build/packages/

RUN pacstall -BPNs -I packages/weblate/weblate.pacscript \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/pacstall /var/cache/apt/archives/*

FROM scratch AS artifact
COPY --from=builder /build/*.deb /
