#!/usr/bin/env bash
# Render docker/Dockerfile.in + docker/distros/*.apt → committed Dockerfiles.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/docker/Dockerfile.in"

render() {
  local from_image="$1"
  local apt_file="$2"
  local out="$3"
  local tmp
  tmp="$(mktemp)"
  export FROM_IMAGE="${from_image}"
  export APT_TOOLCHAIN
  APT_TOOLCHAIN="$(cat "${apt_file}")"
  python3 -c '
import os, pathlib, sys
tmpl = pathlib.Path(sys.argv[1]).read_text()
out = tmpl.replace("@FROM_IMAGE@", os.environ["FROM_IMAGE"]).replace("@APT_TOOLCHAIN@", os.environ["APT_TOOLCHAIN"])
pathlib.Path(sys.argv[2]).write_text(out)
' "${TEMPLATE}" "${tmp}"
  mv "${tmp}" "${out}"
  echo "wrote ${out}"
}

render "debian:trixie" \
  "${ROOT}/docker/distros/debian-trixie.apt" \
  "${ROOT}/docker/Dockerfile"
render "ubuntu:26.04" \
  "${ROOT}/docker/distros/ubuntu-26.04.apt" \
  "${ROOT}/docker/Dockerfile.ubuntu-26.04"
