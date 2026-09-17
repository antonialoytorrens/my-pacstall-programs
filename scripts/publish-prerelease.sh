#!/usr/bin/env bash
# Publish a GitHub prerelease for one package (PACKAGE=<name>).
# Creates a draft, uploads assets, verifies names/sizes, then publishes.
# Tag/title use the package name prefix so Releases stay distinguishable in the monorepo.
# Version is read from pkgver="..." in packages/<name>/<name>.pacscript.
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${PACKAGE:?PACKAGE is required}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISCOVER="${REPO_ROOT}/scripts/discover.sh"
RETRY="${REPO_ROOT}/scripts/retry-5xx.sh"

gh_retry() {
  "${RETRY}" gh "$@"
}

MAX_RETRIES="${RETRY_5XX_MAX_RETRIES:-20}"
INITIAL_DELAY="${RETRY_5XX_INITIAL_DELAY:-60}"
MAX_DELAY="${RETRY_5XX_MAX_DELAY:-900}"

VERSION="$("${DISCOVER}" pkgver "${PACKAGE}")"
TIMESTAMP="$(date -u +%Y%m%d%H%M%S)"
TAG="${PACKAGE}-${VERSION}-${TIMESTAMP}"
RELEASE_NAME="${TAG}"

mapfile -t PKGS < <(
  {
    ls "${PACKAGE}"_[0-9]*_*.deb 2>/dev/null || true
    ls "${PACKAGE}"-*_*.deb 2>/dev/null || true
  } | sort -u
)

if [ "${#PKGS[@]}" -eq 0 ]; then
  echo "No ${PACKAGE}_*.deb / ${PACKAGE}-*.deb artifacts found" >&2
  exit 1
fi

ASSETS=()
NOTES="package: \`${PACKAGE}\` · commit [\`${GITHUB_SHA::7}\`](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA})"
NOTES+=$'\n\n'
NOTES+="| Package | SHA256 |"
NOTES+=$'\n'
NOTES+="|---------|--------|"
NOTES+=$'\n'

for PKG in "${PKGS[@]}"; do
  test -f "${PKG}"
  dpkg-deb -I "${PKG}" >/dev/null
  CHECKSUM_FILE="${PKG}.sha256"
  sha256sum "${PKG}" > "${CHECKSUM_FILE}"
  SHA256="$(awk '{print $1}' "${CHECKSUM_FILE}")"
  ASSETS+=("${PKG}" "${CHECKSUM_FILE}")
  NOTES+="| \`${PKG}\` | \`${SHA256}\` |"
  NOTES+=$'\n'
done

verify_assets() {
  local json
  json="$(gh_retry release view "${TAG}" --json assets)"
  python3 -c '
import json, os, sys
payload = json.loads(sys.argv[1])
remote = {a.get("name", ""): int(a.get("size") or 0) for a in payload.get("assets") or []}
ok = True
for path in sys.argv[2:]:
    name = os.path.basename(path)
    size = os.path.getsize(path)
    got = remote.get(name)
    if got != size:
        print(f"asset mismatch {name}: remote={got!r} local={size}", file=sys.stderr)
        ok = False
if not ok:
    raise SystemExit(1)
' "${json}" "${ASSETS[@]}"
}

ensure_draft() {
  local is_draft
  if is_draft="$(gh_retry release view "${TAG}" --json isDraft --jq .isDraft 2>/dev/null)"; then
    if [ "${is_draft}" = "true" ]; then
      echo "Reusing draft ${TAG}"
      return 0
    fi
    echo "Release ${TAG} is already published; verifying assets" >&2
    verify_assets
    echo "Published release ${TAG} already has complete assets"
    exit 0
  fi
  gh_retry release create "${TAG}" \
    --draft \
    --prerelease \
    --title "${RELEASE_NAME}" \
    --notes "${NOTES}"
}

ensure_draft

delay="${INITIAL_DELAY}"
round=0
while true; do
  for asset in "${ASSETS[@]}"; do
    echo "Uploading ${asset}"
    gh_retry release upload "${TAG}" "${asset}" --clobber
  done
  if verify_assets; then
    break
  fi
  round=$((round + 1))
  if [ "${round}" -gt "${MAX_RETRIES}" ]; then
    echo "Assets not verified after ${MAX_RETRIES} retries; leaving draft ${TAG}" >&2
    exit 1
  fi
  echo "Asset verification failed, retrying uploads in ${delay}s" >&2
  sleep "${delay}"
  delay=$((delay * 2))
  if [ "${delay}" -gt "${MAX_DELAY}" ]; then
    delay="${MAX_DELAY}"
  fi
done

echo "Publishing ${TAG}"
gh_retry release edit "${TAG}" --draft=false --prerelease
