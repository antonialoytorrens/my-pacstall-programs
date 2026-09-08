#!/usr/bin/env bash
# Publish a GitHub prerelease for one package (PACKAGE=gatus|glitchtip|weblate|wger).
# Tag/title use the package name prefix so Releases stay distinguishable in the monorepo.
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${PACKAGE:?PACKAGE is required (gatus|glitchtip|weblate|wger)}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/packages/${PACKAGE}/VERSION"

if [ ! -f "${VERSION_FILE}" ]; then
  echo "Missing version file: ${VERSION_FILE}" >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
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

gh release create "${TAG}" "${ASSETS[@]}" \
  --prerelease \
  --title "${RELEASE_NAME}" \
  --notes "${NOTES}"
