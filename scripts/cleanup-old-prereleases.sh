#!/usr/bin/env bash
# cleanup-old-prereleases.sh — keep the newest KEEP_COUNT GitHub prereleases per package.
# Packages are discovered via scripts/discover.sh (packages/*/ + docker/*/).
# Stable (non-prerelease) releases are never touched.
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

KEEP_COUNT="${KEEP_COUNT:-3}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISCOVER="${REPO_ROOT}/scripts/discover.sh"

if ! [[ "${KEEP_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "KEEP_COUNT must be a positive integer, got: ${KEEP_COUNT}" >&2
  exit 1
fi

mapfile -t PACKAGES < <("${DISCOVER}" list)

if [ "${#PACKAGES[@]}" -eq 0 ]; then
  echo "No packages found (need packages/<name>/<name>.pacscript + docker/<name>/Dockerfile*)" >&2
  exit 1
fi

# Longest name first so foo-bar wins over foo when matching tag prefixes.
mapfile -t PACKAGES_BY_LEN < <(printf '%s\n' "${PACKAGES[@]}" | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)

echo "Packages: ${PACKAGES[*]}"
echo "Keeping ${KEEP_COUNT} newest prerelease(s) per package"

mapfile -t ROWS < <(
  gh release list --repo "${REPO}" --limit 1000 --json tagName,publishedAt,isPrerelease,isDraft \
    --jq '.[] | "\(.tagName)|\(.publishedAt)|\(.isPrerelease)|\(.isDraft)"'
)

declare -A PKG_ROWS=()
for pkg in "${PACKAGES[@]}"; do
  PKG_ROWS["${pkg}"]=""
done

for row in "${ROWS[@]:-}"; do
  IFS='|' read -r tag published is_pre is_draft <<<"${row}"
  if [ "${is_pre}" != "true" ] || [ "${is_draft}" = "true" ]; then
    continue
  fi
  matched=""
  for pkg in "${PACKAGES_BY_LEN[@]}"; do
    case "${tag}" in
      "${pkg}"-*)
        matched="${pkg}"
        break
        ;;
    esac
  done
  if [ -z "${matched}" ]; then
    continue
  fi
  PKG_ROWS["${matched}"]+="${published}|${tag}"$'\n'
done

deleted=0
for pkg in "${PACKAGES[@]}"; do
  rows="${PKG_ROWS[${pkg}]:-}"
  if [ -z "${rows}" ]; then
    echo "${pkg}: 0 prereleases"
    continue
  fi

  mapfile -t sorted < <(printf '%s' "${rows}" | grep -v '^$' | sort -r)
  total="${#sorted[@]}"
  keep=$((total < KEEP_COUNT ? total : KEEP_COUNT))
  echo "${pkg}: ${total} prerelease(s), keeping ${keep}"

  if [ "${total}" -le "${KEEP_COUNT}" ]; then
    continue
  fi

  for ((i = KEEP_COUNT; i < total; i++)); do
    IFS='|' read -r _published tag <<<"${sorted[i]}"
    echo "  delete ${tag}"
    gh release delete "${tag}" --repo "${REPO}" --yes --cleanup-tag
    deleted=$((deleted + 1))
  done
done

echo "Deleted ${deleted}"
