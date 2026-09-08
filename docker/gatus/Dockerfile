# syntax=docker/dockerfile:1
# Platform is set by CI/Makefile via --platform (pacstall cannot cross-build).
FROM debian:trixie AS builder

ARG PACSTALL_VERSION=6.4.2
ARG PACSTALL_REVISION=pacstall1
ARG SPDX_LICENSES_VERSION=3.27.0
ARG SPDX_LICENSES_REVISION=+ds-1
ARG GO_VERSION=1.26.8
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/go/bin:${PATH}"

RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    ca-certificates sudo curl git

# Go: official toolchain (amd64/arm64/armv6l). Same steps on every arch —
# Debian golang is too old for gatus (needs go1.26+).
RUN ARCH="$(dpkg --print-architecture)" \
  && case "${ARCH}" in \
       amd64) GOARCH=amd64 ;; \
       arm64) GOARCH=arm64 ;; \
       armhf) GOARCH=armv6l ;; \
       *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
     esac \
  && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" \
    | tar -C /usr/local -xz \
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

RUN pacstall -BPNs -I packages/gatus/gatus.pacscript:pkgbase \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/pacstall /var/cache/apt/archives/*

FROM scratch AS artifact
COPY --from=builder /build/*.deb /
