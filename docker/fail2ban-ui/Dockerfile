# syntax=docker/dockerfile:1
# Platform is set by CI/Makefile via --platform (pacstall cannot cross-build).
FROM debian:trixie AS builder

ARG PACSTALL_VERSION=6.4.2
ARG PACSTALL_REVISION=pacstall1
ARG SPDX_LICENSES_VERSION=3.27.0
ARG SPDX_LICENSES_REVISION=+ds-1
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    ca-certificates sudo curl git

# Go 1.26 from trixie-backports (Debian golang in main is too old).
# Pin so pacstall makedepends keep the backports toolchain.
RUN printf 'deb http://deb.debian.org/debian trixie-backports main\n' \
      > /etc/apt/sources.list.d/trixie-backports.list \
  && printf 'Package: golang*\nPin: release n=trixie-backports\nPin-Priority: 990\n' \
      > /etc/apt/preferences.d/golang-backports \
  && apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends golang \
  && go version

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

RUN set -e \
  && pacstall -BPNs -I packages/fail2ban-ui/fail2ban-ui.pacscript \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/pacstall /var/cache/apt/archives/*

FROM scratch AS artifact
COPY --from=builder /build/*.deb /
