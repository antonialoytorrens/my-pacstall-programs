#!/usr/bin/env bash
# cleanup-old-prereleases.sh — delete GitHub prereleases older than RETENTION_DAYS (default 30).
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

RETENTION_DAYS="${RETENTION_DAYS:-30}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

if ! command -v python3 &>/dev/null; then
  echo "python3 is required" >&2
  exit 1
fi

CUTOFF="$(python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) - timedelta(days=int('${RETENTION_DAYS}'))).strftime('%Y-%m-%dT%H:%M:%SZ'))")"

mapfile -t ROWS < <(
  gh release list --repo "${REPO}" --limit 1000 --json tagName,publishedAt,isPrerelease,isDraft \
    --jq '.[] | "\(.tagName)|\(.publishedAt)|\(.isPrerelease)|\(.isDraft)"'
)

deleted=0
for row in "${ROWS[@]:-}"; do
  IFS='|' read -r tag published is_pre is_draft <<<"${row}"
  if [ "${is_pre}" != "true" ] || [ "${is_draft}" = "true" ]; then
    continue
  fi
  if [ -z "${published}" ] || [ "${published}" \> "${CUTOFF}" ] || [ "${published}" = "${CUTOFF}" ]; then
    continue
  fi
  gh release delete "${tag}" --repo "${REPO}" --yes --cleanup-tag
  deleted=$((deleted + 1))
done

echo "Deleted ${deleted}"
