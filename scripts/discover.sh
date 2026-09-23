#!/usr/bin/env bash
# discover.sh — convention-based package discovery (no per-package meta).
#
# A package exists when packages/<name>/<name>.pacscript is present.
# Distros come from shared docker/Dockerfile* (not docker/<pkg>/).
#
# Version = literal pkgver="..." in the pacscript (no bash expansion).
#
# Usage:
#   discover.sh list
#   discover.sh pkgver <pkg>
#   discover.sh pkgrel <pkg>
#   discover.sh arches <pkg>
#   discover.sh pkgnames <pkg>
#   discover.sh dockerfiles
#   discover.sh packagelist
#   discover.sh srclist
#   discover.sh make-targets
#   discover.sh build <target>
#   discover.sh build-matrix [pkg...]
#   discover.sh publish-matrix [pkg...]
#   discover.sh check-matrix
#   discover.sh changed [base_sha]
#   discover.sh unpublished [pkg...]
#   discover.sh upstream <pkg>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pacscript_path() {
  local pkg="$1"
  printf '%s\n' "${ROOT}/packages/${pkg}/${pkg}.pacscript"
}

is_package() {
  local pkg="$1"
  [ -f "$(pacscript_path "${pkg}")" ]
}

list_packages() {
  local d name
  for d in "${ROOT}"/packages/*/; do
    [ -d "${d}" ] || continue
    name="$(basename "${d}")"
    if is_package "${name}"; then
      printf '%s\n' "${name}"
    fi
  done | sort
}

pkgver_of() {
  local pkg="$1"
  local ps ver
  ps="$(pacscript_path "${pkg}")"
  if [ ! -f "${ps}" ]; then
    echo "pacscript not found: ${ps}" >&2
    return 1
  fi
  ver="$(sed -n 's/^pkgver="\([^"]*\)".*/\1/p' "${ps}" | head -n1)"
  if [ -z "${ver}" ]; then
    echo "pkgver=\"...\" not found in ${ps}" >&2
    return 1
  fi
  printf '%s\n' "${ver}"
}

pkgrel_of() {
  local pkg="$1"
  local ps rel
  ps="$(pacscript_path "${pkg}")"
  if [ ! -f "${ps}" ]; then
    echo "pacscript not found: ${ps}" >&2
    return 1
  fi
  rel="$(sed -n 's/^pkgrel="\([^"]*\)".*/\1/p' "${ps}" | head -n1)"
  printf '%s\n' "${rel:-1}"
}

expected_versioned_debs() {
  local pkg="$1"
  local ver rel multi suffix arch dockerfile distro release sub sub_arch
  ver="$(pkgver_of "${pkg}")"
  rel="$(pkgrel_of "${pkg}")"
  multi=false
  if [ "$(dockerfile_count)" -gt 1 ]; then
    multi=true
  fi
  while IFS='|' read -r dockerfile distro release; do
    [ -n "${dockerfile}" ] || continue
    suffix="$(deb_suffix_of "${distro}" "${release}")"
    while IFS= read -r arch; do
      [ -n "${arch}" ] || continue
      if [ "${multi}" = true ]; then
        printf '%s\n' "${pkg}_${ver}-pacstall${rel}~${suffix}_${arch}.deb"
      else
        printf '%s\n' "${pkg}_${ver}-pacstall${rel}_${arch}.deb"
      fi
      while IFS= read -r sub; do
        [ -n "${sub}" ] || continue
        # Only expect this subpackage for arches it declares (or inherits).
        while IFS= read -r sub_arch; do
          [ "${sub_arch}" = "${arch}" ] || continue
          if [ "${multi}" = true ]; then
            printf '%s\n' "${sub}_${ver}-pacstall${rel}~${suffix}_${arch}.deb"
          else
            printf '%s\n' "${sub}_${ver}-pacstall${rel}_${arch}.deb"
          fi
        done < <(pkgname_arches_of "${pkg}" "${sub}")
      done < <(arch_specific_subpackages_of "${pkg}")
    done < <(arches_of "${pkg}")
    # Architecture: all helpers — one .deb per distro (from amd64 build).
    while IFS= read -r sub; do
      [ -n "${sub}" ] || continue
      if [ "${multi}" = true ]; then
        printf '%s\n' "${sub}_${ver}-pacstall${rel}~${suffix}_all.deb"
      else
        printf '%s\n' "${sub}_${ver}-pacstall${rel}_all.deb"
      fi
    done < <(all_arch_subpackages_of "${pkg}")
  done < <(dockerfiles_of)
}

unpublished_packages() {
  local selected=("$@")
  local pkg first json_pkgs json_expected line nfirst
  local releases status

  if [ "${#selected[@]}" -eq 0 ]; then
    return 0
  fi

  json_pkgs='['
  json_expected='{'
  first=true
  for pkg in "${selected[@]}"; do
    [ -n "${pkg}" ] || continue
    is_package "${pkg}" || continue
    if [ "${first}" = true ]; then
      first=false
    else
      json_pkgs+=','
      json_expected+=','
    fi
    json_pkgs+="$(json_escape "${pkg}")"
    json_expected+="$(json_escape "${pkg}")"
    json_expected+=':['
    nfirst=true
    while IFS= read -r line; do
      [ -n "${line}" ] || continue
      if [ "${nfirst}" = true ]; then
        nfirst=false
      else
        json_expected+=','
      fi
      json_expected+="$(json_escape "${line}")"
    done < <(expected_versioned_debs "${pkg}")
    json_expected+=']'
  done
  json_pkgs+=']'
  json_expected+='}'

  if [ -z "${GITHUB_REPOSITORY:-}" ] || { [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${GH_TOKEN:-}" ]; }; then
    echo "unpublished: no GitHub credentials; not skipping" >&2
    printf '%s\n' "${selected[@]}"
    return 0
  fi

  status=0
  releases="$("${ROOT}/scripts/retry-5xx.sh" gh api --paginate "repos/${GITHUB_REPOSITORY}/releases")" || status=$?
  if [ "${status}" -ne 0 ]; then
    echo "unpublished: failed to list releases; not skipping" >&2
    printf '%s\n' "${selected[@]}"
    return 0
  fi

  status=0
  EXPECTED_JSON="${json_expected}" SELECTED_JSON="${json_pkgs}" python3 -c '
import json, os, sys

raw = sys.stdin.read()
decoder = json.JSONDecoder()
idx = 0
releases = []
while idx < len(raw):
    while idx < len(raw) and raw[idx].isspace():
        idx += 1
    if idx >= len(raw):
        break
    obj, end = decoder.raw_decode(raw, idx)
    idx = end
    if isinstance(obj, list):
        releases.extend(obj)
    else:
        releases.append(obj)

expected = json.loads(os.environ["EXPECTED_JSON"])
order = json.loads(os.environ["SELECTED_JSON"])
published = set()
for rel in releases:
    if rel.get("draft") or not rel.get("prerelease"):
        continue
    names = {a.get("name") or "" for a in (rel.get("assets") or [])}
    for pkg, need in expected.items():
        if pkg in published or not need:
            continue
        if all(n in names for n in need):
            published.add(pkg)
            print(f"skip {pkg}: already published for current pkgver+pkgrel", file=sys.stderr)

for pkg in order:
    if pkg not in published:
        print(pkg)
' <<<"${releases}" || status=$?
  if [ "${status}" -ne 0 ]; then
    echo "unpublished: failed to parse releases; not skipping" >&2
    printf '%s\n' "${selected[@]}"
    return 0
  fi
}

arches_of() {
  local pkg="$1"
  local ps line
  ps="$(pacscript_path "${pkg}")"
  line="$(grep -E "^arch=\(" "${ps}" | head -n1 || true)"
  if [ -z "${line}" ]; then
    echo "amd64"
    return 0
  fi
  printf '%s\n' "${line}" | sed -E "s/^arch=\(//; s/\).*//; s/['\"]//g" | tr -s '[:space:]' '\n' | grep -v '^$' || true
}

pkgnames_of() {
  local pkg="$1"
  local ps line
  ps="$(pacscript_path "${pkg}")"
  if line="$(grep -E '^pkgname=\(' "${ps}" | head -n1)"; then
    printf '%s\n' "${line}" | sed -E "s/^pkgname=\(//; s/\).*//; s/['\"]//g" | tr -s '[:space:]' '\n' | grep -v '^$'
    return 0
  fi
  if line="$(grep -E '^pkgname="' "${ps}" | head -n1)"; then
    printf '%s\n' "${line}" | sed -n 's/^pkgname="\([^"]*\)".*/\1/p'
    return 0
  fi
  printf '%s\n' "${pkg}"
}

# True when package_<name>() sets arch=('all') (Architecture: all helper).
pkgname_is_all_arch() {
  local pkg="$1" name="$2"
  local line
  line="$(pkgname_arch_line_of "${pkg}" "${name}")"
  [ "${line}" = "all" ]
}

# Print arch tokens from package_<name>() arch=(...), or empty if unset.
pkgname_arch_line_of() {
  local pkg="$1" name="$2"
  local ps
  ps="$(pacscript_path "${pkg}")"
  awk -v fn="package_${name}" '
    $0 ~ "^" fn "\\(\\)" { infn = 1; next }
    infn && /^[a-zA-Z_][a-zA-Z0-9_-]*\(/ { exit }
    infn && /^[[:space:]]*arch=\(/ {
      line = $0
      sub(/^[[:space:]]*arch=\(/, "", line)
      sub(/\).*/, "", line)
      gsub(/['\''"]/, "", line)
      print line
      exit
    }
  ' "${ps}"
}

# Architectures for a split subpackage: override arch= if set, else pkgbase.
# Prints one arch per line. For arch=('all') prints a single "all".
pkgname_arches_of() {
  local pkg="$1" name="$2"
  local line a
  line="$(pkgname_arch_line_of "${pkg}" "${name}")"
  if [ -z "${line}" ]; then
    arches_of "${pkg}"
    return 0
  fi
  for a in ${line}; do
    printf '%s\n' "${a}"
  done
}

# Subpackages that are not Architecture: all (may still restrict arches).
arch_specific_subpackages_of() {
  local pkg="$1" name
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    [ "${name}" = "${pkg}" ] && continue
    if pkgname_is_all_arch "${pkg}" "${name}"; then
      continue
    fi
    printf '%s\n' "${name}"
  done < <(pkgnames_of "${pkg}")
}

# Subpackages with arch=('all') (uploaded once per distro from amd64).
all_arch_subpackages_of() {
  local pkg="$1" name
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    [ "${name}" = "${pkg}" ] && continue
    if pkgname_is_all_arch "${pkg}" "${name}"; then
      printf '%s\n' "${name}"
    fi
  done < <(pkgnames_of "${pkg}")
}

# Print: dockerfile|distribution|release  (shared docker/, skip Dockerfile.in)
dockerfiles_of() {
  local f base rest distro release
  if [ -f "${ROOT}/docker/Dockerfile" ]; then
    printf '%s\n' "Dockerfile|debian|trixie"
  fi
  for f in "${ROOT}/docker"/Dockerfile.*; do
    [ -f "${f}" ] || continue
    base="$(basename "${f}")"
    [ "${base}" = "Dockerfile.in" ] && continue
    rest="${base#Dockerfile.}"
    if [[ "${rest}" =~ ^([a-z]+)-(.+)$ ]]; then
      distro="${BASH_REMATCH[1]}"
      release="${BASH_REMATCH[2]}"
      printf '%s\n' "${base}|${distro}|${release}"
    else
      echo "unsupported dockerfile name: ${base} (want Dockerfile.<distro>-<release>)" >&2
      return 1
    fi
  done
}

dockerfile_count() {
  dockerfiles_of | wc -l
}

deb_suffix_of() {
  local distro="$1" release="$2"
  case "${distro}" in
    debian)
      case "${release}" in
        trixie) printf '%s\n' "debian13" ;;
        bookworm) printf '%s\n' "debian12" ;;
        *) echo "unknown debian release: ${release}" >&2; return 1 ;;
      esac
      ;;
    ubuntu)
      printf '%s\n' "ubuntu${release}"
      ;;
    *)
      echo "unknown distro: ${distro}" >&2
      return 1
      ;;
  esac
}

emit_packagelist() {
  local pkg names n count
  while IFS= read -r pkg; do
    mapfile -t names < <(pkgnames_of "${pkg}")
    count="${#names[@]}"
    if [ "${count}" -gt 1 ]; then
      printf '%s:pkgbase\n' "${pkg}"
      for n in "${names[@]}"; do
        printf '%s:%s\n' "${pkg}" "${n}"
      done
    else
      printf '%s\n' "${pkg}"
    fi
  done < <(list_packages)
}

emit_srclist() {
  list_packages
}

make_targets() {
  local pkg arch distro release dockerfile default_df count
  count="$(dockerfile_count)"
  while IFS= read -r pkg; do
    default_df=""
    while IFS='|' read -r dockerfile distro release; do
      [ -n "${dockerfile}" ] || continue
      if [ "${dockerfile}" = "Dockerfile" ]; then
        default_df=1
      fi
      for arch in $(arches_of "${pkg}" | tr '\n' ' '); do
        if [ "${count}" -eq 1 ] && [ "${dockerfile}" = "Dockerfile" ]; then
          printf '%s-%s\n' "${pkg}" "${arch}"
        else
          printf '%s-%s-%s-%s\n' "${pkg}" "${distro}" "${release}" "${arch}"
        fi
      done
    done < <(dockerfiles_of)
    if [ "${count}" -gt 1 ] && [ -n "${default_df}" ]; then
      for arch in $(arches_of "${pkg}" | tr '\n' ' '); do
        printf '%s-%s\n' "${pkg}" "${arch}"
      done
    fi
  done < <(list_packages)
}

parse_target() {
  # Sets: PKG DISTRO RELEASE ARCH DOCKERFILE TARGET_KIND
  local target="$1"
  local pkg arch distro release rest
  PKG="" DISTRO="" RELEASE="" ARCH="" DOCKERFILE="" TARGET_KIND=""

  if [[ "${target}" =~ ^(.+)-(amd64|arm64|armhf)$ ]]; then
    rest="${BASH_REMATCH[1]}"
    arch="${BASH_REMATCH[2]}"
  else
    echo "invalid target (need …-amd64|arm64|armhf): ${target}" >&2
    return 1
  fi

  if is_package "${rest}"; then
    PKG="${rest}"
    ARCH="${arch}"
    if [ -f "${ROOT}/docker/Dockerfile" ]; then
      DOCKERFILE="Dockerfile"
      DISTRO="debian"
      RELEASE="trixie"
    else
      IFS='|' read -r DOCKERFILE DISTRO RELEASE < <(dockerfiles_of | head -n1)
    fi
    if [ "$(dockerfile_count)" -gt 1 ]; then
      TARGET_KIND="alias"
    else
      TARGET_KIND="simple"
    fi
    return 0
  fi

  local cand
  mapfile -t pkgs < <(list_packages | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
  for cand in "${pkgs[@]}"; do
    case "${rest}" in
      "${cand}"-*)
        local suffix="${rest#"${cand}"-}"
        if [[ "${suffix}" =~ ^([a-z]+)-(.+)$ ]]; then
          distro="${BASH_REMATCH[1]}"
          release="${BASH_REMATCH[2]}"
          PKG="${cand}"
          DISTRO="${distro}"
          RELEASE="${release}"
          ARCH="${arch}"
          if [ "${distro}" = "debian" ] && [ "${release}" = "trixie" ]; then
            DOCKERFILE="Dockerfile"
          else
            DOCKERFILE="Dockerfile.${distro}-${release}"
          fi
          if [ ! -f "${ROOT}/docker/${DOCKERFILE}" ]; then
            echo "dockerfile not found: docker/${DOCKERFILE}" >&2
            return 1
          fi
          TARGET_KIND="full"
          return 0
        fi
        ;;
    esac
  done

  echo "unknown package target: ${target}" >&2
  return 1
}

platform_of() {
  case "$1" in
    amd64) echo linux/amd64 ;;
    arm64) echo linux/arm64 ;;
    armhf) echo linux/arm/v7 ;;
    *) echo "unsupported arch: $1" >&2; return 1 ;;
  esac
}

runner_of() {
  case "$1" in
    amd64) echo ubuntu-latest ;;
    arm64|armhf) echo ubuntu-24.04-arm ;;
    *) echo ubuntu-latest ;;
  esac
}

qemu_of() {
  case "$1" in
    armhf) echo true ;;
    *) echo false ;;
  esac
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

build_target() {
  local target="$1"
  parse_target "${target}"
  local platform args=()
  platform="$(platform_of "${ARCH}")"

  emit_packagelist > "${ROOT}/packagelist"
  emit_srclist > "${ROOT}/srclist"

  args=(docker buildx build --platform "${platform}"
    -f "${ROOT}/docker/${DOCKERFILE}"
    --build-arg "PACKAGE=${PKG}"
    --target artifact
    --output "${ROOT}/."
    "${ROOT}"
  )

  echo "+ ${args[*]}"
  "${args[@]}"
}

build_matrix_json() {
  local selected=("$@")
  local pkg dockerfile distro release arch first=true multi
  if [ "${#selected[@]}" -eq 0 ]; then
    mapfile -t selected < <(list_packages)
  fi
  multi=false
  if [ "$(dockerfile_count)" -gt 1 ]; then
    multi=true
  fi
  printf '['
  for pkg in "${selected[@]}"; do
    [ -n "${pkg}" ] || continue
    is_package "${pkg}" || continue
    while IFS='|' read -r dockerfile distro release; do
      [ -n "${dockerfile}" ] || continue
      while IFS= read -r arch; do
        [ -n "${arch}" ] || continue
        local target suffix relnum
        if [ "${multi}" = true ]; then
          target="${pkg}-${distro}-${release}-${arch}"
        else
          target="${pkg}-${arch}"
        fi
        suffix="$(deb_suffix_of "${distro}" "${release}")"
        relnum="${suffix#"${distro}"}"
        if [ "${first}" = true ]; then
          first=false
        else
          printf ','
        fi
        printf '{"package":%s,"distribution":%s,"release":%s,"dockerfile":%s,"arch":%s,"runner":%s,"qemu":%s,"target":%s,"multi_distro":%s,"timeout_minutes":360,"deb_suffix":%s,"release_number":%s}' \
          "$(json_escape "${pkg}")" \
          "$(json_escape "${distro}")" \
          "$(json_escape "${release}")" \
          "$(json_escape "${dockerfile}")" \
          "$(json_escape "${arch}")" \
          "$(json_escape "$(runner_of "${arch}")")" \
          "$(qemu_of "${arch}")" \
          "$(json_escape "${target}")" \
          "${multi}" \
          "$(json_escape "${suffix}")" \
          "$(json_escape "${relnum}")"
      done < <(arches_of "${pkg}")
    done < <(dockerfiles_of)
  done
  printf ']\n'
}

publish_matrix_json() {
  local selected=("$@")
  local pkg dockerfile distro release arch first=true multi suffix glob sub
  local globs first_glob want sub_arch
  if [ "${#selected[@]}" -eq 0 ]; then
    mapfile -t selected < <(list_packages)
  fi
  multi=false
  if [ "$(dockerfile_count)" -gt 1 ]; then
    multi=true
  fi
  printf '['
  for pkg in "${selected[@]}"; do
    [ -n "${pkg}" ] || continue
    is_package "${pkg}" || continue
    globs="["
    first_glob=true
    while IFS='|' read -r dockerfile distro release; do
      [ -n "${dockerfile}" ] || continue
      suffix="$(deb_suffix_of "${distro}" "${release}")"
      while IFS= read -r arch; do
        [ -n "${arch}" ] || continue
        if [ "${multi}" = true ]; then
          glob="${pkg}_*~${suffix}_${arch}.deb"
        else
          glob="${pkg}_*_${arch}.deb"
        fi
        if [ "${first_glob}" = true ]; then
          first_glob=false
        else
          globs+=","
        fi
        globs+="$(json_escape "${glob}")"
        while IFS= read -r sub; do
          [ -n "${sub}" ] || continue
          # Only expect this subpackage for arches it declares (or inherits).
          want=false
          while IFS= read -r sub_arch; do
            if [ "${sub_arch}" = "${arch}" ]; then
              want=true
              break
            fi
          done < <(pkgname_arches_of "${pkg}" "${sub}")
          [ "${want}" = true ] || continue
          if [ "${multi}" = true ]; then
            glob="${sub}_*~${suffix}_${arch}.deb"
          else
            glob="${sub}_*_${arch}.deb"
          fi
          globs+=","
          globs+="$(json_escape "${glob}")"
        done < <(arch_specific_subpackages_of "${pkg}")
      done < <(arches_of "${pkg}")
      # Architecture: all helpers — one glob per distro (amd64 artifact).
      while IFS= read -r sub; do
        [ -n "${sub}" ] || continue
        if [ "${multi}" = true ]; then
          glob="${sub}_*~${suffix}_all.deb"
        else
          glob="${sub}_*_all.deb"
        fi
        if [ "${first_glob}" = true ]; then
          first_glob=false
        else
          globs+=","
        fi
        globs+="$(json_escape "${glob}")"
      done < <(all_arch_subpackages_of "${pkg}")
    done < <(dockerfiles_of)
    globs+="]"
    if [ "${first}" = true ]; then
      first=false
    else
      printf ','
    fi
    printf '{"package":%s,"expected_globs":%s}' "$(json_escape "${pkg}")" "${globs}"
  done
  printf ']\n'
}

check_matrix_json() {
  local pkg first=true
  printf '['
  while IFS= read -r pkg; do
    if [ "${first}" = true ]; then
      first=false
    else
      printf ','
    fi
    printf '{"package":%s,"title_prefix":%s}' \
      "$(json_escape "${pkg}")" \
      "$(json_escape "${pkg}")"
  done < <(list_packages)
  printf ']\n'
}

changed_packages() {
  local base_sha="${1:-}"
  local force_all=false
  local pkg changed

  mapfile -t ALL < <(list_packages)

  if [ -z "${base_sha}" ] || [ "${base_sha}" = "0000000000000000000000000000000000000000" ]; then
    force_all=true
  else
    changed="$(git -C "${ROOT}" diff --name-only "${base_sha}"...HEAD 2>/dev/null || true)"
    # Only the build workflow itself forces rebuild-all. packagelist/srclist,
    # Makefile, settings, scripts/, docker/, etc. must not (e.g. bb4cffc).
    if printf '%s\n' "${changed}" | grep -qE '^\.github/workflows/build\.yml'; then
      force_all=true
    fi
  fi

  if [ "${force_all}" = true ]; then
    printf '%s\n' "${ALL[@]}"
    return 0
  fi

  local out=()
  for pkg in "${ALL[@]}"; do
    if printf '%s\n' "${changed}" | grep -qE "^packages/${pkg}/"; then
      out+=("${pkg}")
    fi
  done
  if [ "${#out[@]}" -gt 0 ]; then
    printf '%s\n' "${out[@]}"
  fi
}

resolve_upstream() {
  # Prints: github:owner/repo  OR  anitya:ID
  # 1) anitya.cfg (package=id)
  # 2) infer github from pacscript source=/url=
  local pkg="$1"
  local ps line id

  id="$(sed -n "s/^${pkg}=//p" "${ROOT}/anitya.cfg" 2>/dev/null | head -n1 || true)"
  if [ -n "${id}" ]; then
    printf 'anitya:%s\n' "${id}"
    return 0
  fi

  ps="$(pacscript_path "${pkg}")"
  line="$(grep -E 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "${ps}" \
    | grep -v maintainer \
    | head -n1 || true)"
  if [ -n "${line}" ]; then
    if [[ "${line}" =~ github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+) ]]; then
      printf 'github:%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
      return 0
    fi
  fi

  line="$(grep -E '^url="https://github\.com/' "${ps}" | head -n1 || true)"
  if [ -n "${line}" ]; then
    if [[ "${line}" =~ github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+) ]]; then
      printf 'github:%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
      return 0
    fi
  fi

  echo "cannot resolve upstream for ${pkg}: add an entry to anitya.cfg or a GitHub URL in the pacscript" >&2
  return 1
}

cmd="${1:-}"
shift || true

case "${cmd}" in
  list)
    list_packages
    ;;
  pkgver)
    pkgver_of "${1:?package required}"
    ;;
  pkgrel)
    pkgrel_of "${1:?package required}"
    ;;
  unpublished)
    unpublished_packages "$@"
    ;;
  arches)
    arches_of "${1:?package required}"
    ;;
  pkgnames)
    pkgnames_of "${1:?package required}"
    ;;
  dockerfiles)
    dockerfiles_of
    ;;
  packagelist)
    emit_packagelist
    ;;
  srclist)
    emit_srclist
    ;;
  make-targets)
    make_targets
    ;;
  build)
    build_target "${1:?target required}"
    ;;
  build-matrix)
    build_matrix_json "$@"
    ;;
  publish-matrix)
    publish_matrix_json "$@"
    ;;
  check-matrix)
    check_matrix_json
    ;;
  changed)
    changed_packages "${1:-}"
    ;;
  upstream)
    resolve_upstream "${1:?package required}"
    ;;
  *)
    echo "Usage: $0 list|pkgver|pkgrel|arches|pkgnames|dockerfiles|packagelist|srclist|make-targets|build|build-matrix|publish-matrix|check-matrix|changed|unpublished|upstream" >&2
    exit 2
    ;;
esac
