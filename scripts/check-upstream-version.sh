#!/usr/bin/env bash
#
# check-upstream-version.sh — compare packages/<PACKAGE>/VERSION against upstream.
#
# Required: PACKAGE=gatus|glitchtip|weblate|wger|fail2ban-ui
# Optional: VERSION=<upstream> to skip the remote API
#
# Exit codes:
#   0 — packaged version is up to date
#   1 — a newer stable version is available (prints version to stdout)
#   2 — API or parse error
#
set -euo pipefail

: "${PACKAGE:?PACKAGE is required (gatus|glitchtip|weblate|wger|fail2ban-ui)}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGED_VERSION_FILE="${REPO_ROOT}/packages/${PACKAGE}/VERSION"
CACHE_DIR="${REPO_ROOT}/.cache"
USER_AGENT="${USER_AGENT:-my-pacstall-programs/1.0 (+https://github.com/antonialoytorrens/my-pacstall-programs)}"

if [ ! -f "${PACKAGED_VERSION_FILE}" ]; then
  echo "Packaged version file not found: ${PACKAGED_VERSION_FILE}" >&2
  exit 2
fi

PACKAGED_VERSION="$(tr -d '[:space:]' < "${PACKAGED_VERSION_FILE}")"

fetch_github() {
  local github_repo="$1"
  local api_url="https://api.github.com/repos/${github_repo}/releases/latest"
  local response
  response="$(curl -fsS -A "${USER_AGENT}" \
    -H "Accept: application/vnd.github+json" \
    "${api_url}")" || {
    echo "Failed to query GitHub API: ${api_url}" >&2
    exit 2
  }
  printf '%s' "${response}" | python3 -c '
import json, sys, re
data = json.load(sys.stdin)
tag = data.get("tag_name") or ""
tag = re.sub(r"^v", "", tag.strip())
if not tag:
    raise SystemExit(2)
print(tag)
'
}

fetch_anitya() {
  local project_id="$1"
  local api_url="https://release-monitoring.org/api/v2/versions/?project_id=${project_id}"
  local response parsed
  response="$(curl -fsS -A "${USER_AGENT}" "${api_url}")" || {
    echo "Failed to query Anitya API: ${api_url}" >&2
    exit 2
  }
  parsed="$(printf '%s' "${response}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
stable = data.get("stable_versions") or []
latest = stable[0] if stable else data.get("version") or data.get("latest_version")
created = data.get("latest_version_created_on") or ""
if not latest:
    raise SystemExit(2)
print(f"{latest}\t{created}")
')"
  LATEST_CREATED_ON="${parsed#*$'\t'}"
  printf '%s' "${parsed%%$'\t'*}"
}

if [ -n "${VERSION:-}" ]; then
  LATEST_STABLE="$(printf '%s' "${VERSION}" | tr -d '[:space:]')"
else
  if ! command -v python3 &>/dev/null; then
    echo "python3 is required" >&2
    exit 2
  fi

  LATEST_CREATED_ON=""
  case "${PACKAGE}" in
    gatus)
      LATEST_STABLE="$(fetch_github TwiN/gatus)"
      CACHE_FILE="${CACHE_DIR}/gatus-github-last-check"
      ;;
    wger)
      LATEST_STABLE="$(fetch_github wger-project/wger)"
      CACHE_FILE="${CACHE_DIR}/wger-github-last-check"
      ;;
    glitchtip)
      LATEST_STABLE="$(fetch_anitya 392074)"
      CACHE_FILE="${CACHE_DIR}/glitchtip-anitya-last-check"
      ;;
    weblate)
      LATEST_STABLE="$(fetch_anitya 33597)"
      CACHE_FILE="${CACHE_DIR}/weblate-anitya-last-check"
      ;;
    fail2ban-ui)
      LATEST_STABLE="$(fetch_github swissmakers/fail2ban-ui)"
      CACHE_FILE="${CACHE_DIR}/fail2ban-ui-github-last-check"
      ;;
    *)
      echo "Unknown PACKAGE=${PACKAGE}" >&2
      exit 2
      ;;
  esac

  mkdir -p "${CACHE_DIR}"
  {
    echo "latest_stable_version=${LATEST_STABLE}"
    [ -n "${LATEST_CREATED_ON:-}" ] && echo "latest_version_created_on=${LATEST_CREATED_ON}"
    echo "checked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${CACHE_FILE}"
fi

if [ "${PACKAGED_VERSION}" = "${LATEST_STABLE}" ]; then
  echo "${PACKAGED_VERSION}"
  exit 0
fi

NEWER="$(printf '%s\n%s\n' "${PACKAGED_VERSION}" "${LATEST_STABLE}" | sort -V | tail -1)"
if [ "${NEWER}" = "${LATEST_STABLE}" ]; then
  echo "${LATEST_STABLE}"
  exit 1
fi

echo "${PACKAGED_VERSION}"
exit 0
