# syntax=docker/dockerfile:1
# Platform is set by CI/Makefile via --platform (pacstall cannot cross-build).
FROM debian:trixie AS builder

ARG PACSTALL_VERSION=6.4.2
ARG PACSTALL_REVISION=pacstall1
ARG SPDX_LICENSES_VERSION=3.27.0
ARG SPDX_LICENSES_REVISION=+ds-1
ARG WGER_DOMAIN=wger.localhost.local
ENV DEBIAN_FRONTEND=noninteractive
ENV WGER_DOMAIN=${WGER_DOMAIN}

# rustc in trixie main is too old for cryptography/nh3 let-chains; same on all arches.
RUN echo "deb http://deb.debian.org/debian trixie-backports main" \
      > /etc/apt/sources.list.d/backports.list \
  && apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    ca-certificates sudo curl \
    python3 python3-venv python3-dev python3-pip build-essential pkg-config patch \
    libpq-dev zlib1g-dev libjpeg62-turbo-dev libwebp-dev \
    libssl-dev libffi-dev \
    gettext git tzdata \
    nodejs npm \
  && apt-get install -y -qq -t trixie-backports --no-install-recommends rustc cargo

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

# Pacscript reads domain defaults; allow override via build-arg by sed if needed.
RUN sed -i "s|_wger_domain=\"wger.localhost.local\"|_wger_domain=\"${WGER_DOMAIN}\"|" \
      packages/wger/wger.pacscript \
  && pacstall -BPNs -I packages/wger/wger.pacscript \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/pacstall /var/cache/apt/archives/*

FROM scratch AS artifact
COPY --from=builder /build/*.deb /
