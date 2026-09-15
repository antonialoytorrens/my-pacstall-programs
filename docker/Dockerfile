# syntax=docker/dockerfile:1
# Generated from Dockerfile.in — do not edit by hand (scripts/render-dockerfiles.sh).
# Platform is set by CI/Makefile via --platform (pacstall cannot cross-build).
FROM debian:trixie AS builder

ARG PACSTALL_VERSION=6.4.2
ARG PACSTALL_REVISION=pacstall1
ARG SPDX_LICENSES_VERSION=3.27.0
ARG SPDX_LICENSES_REVISION=+ds-1
ARG PACKAGE
ENV DEBIAN_FRONTEND=noninteractive

RUN echo "deb http://deb.debian.org/debian trixie-backports main" \
      > /etc/apt/sources.list.d/backports.list \
  && printf '%s\n' \
       'Package: golang*' \
       'Pin: release n=trixie-backports' \
       'Pin-Priority: 990' \
       '' \
       'Package: rustc' \
       'Pin: release n=trixie-backports' \
       'Pin-Priority: 990' \
       '' \
       'Package: cargo' \
       'Pin: release n=trixie-backports' \
       'Pin-Priority: 990' \
       > /etc/apt/preferences.d/toolchain-backports \
  && apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
       ca-certificates sudo curl git \
  && apt-get install -y -qq -t trixie-backports --no-install-recommends \
       golang rustc cargo

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

# Split packages: build pkgbase first, install it, then helpers. Else one -I.
RUN set -e \
  && ps="packages/${PACKAGE}/${PACKAGE}.pacscript" \
  && if grep -qE '^pkgname=\(' "${ps}"; then \
       pacstall -BPNs -I "${ps}:${PACKAGE}" \
       && apt-get install -y -qq --no-install-recommends ./${PACKAGE}_*.deb \
       && names="$(sed -nE 's/^pkgname=\((.*)\).*/\1/p' "${ps}" | head -n1 | tr -d "'\"")" \
       && for n in ${names}; do \
            [ "${n}" = "${PACKAGE}" ] && continue; \
            pacstall -BPNs -I "${ps}:${n}"; \
          done; \
     else \
       pacstall -BPNs -I "${ps}"; \
     fi \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/pacstall /var/cache/apt/archives/*

FROM scratch AS artifact
COPY --from=builder /build/*.deb /
