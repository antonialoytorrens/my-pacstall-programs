pkgname="wger"
pkgver="2.6"
pkgrel="1"
arch=('amd64' 'arm64' 'armhf')
url="https://wger.de/"
license=('AGPL-3.0-or-later')
pkgdesc="wger Workout Manager (bundled venv, native systemd, dbconfig-pgsql)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/wger-deb>")
external_connection=true

_wger_domain="wger.localhost.local"
_wger_db_name="wger"
_wger_db_user="wger"
_wger_db_host="127.0.0.1"
_wger_http_port="38437"

_src="wger-${pkgver}"
_install_prefix="/opt/wger"
_python="python3"

# lingua-language-detector on PyPI is wheel-only (amd64/arm64); no armhf/sdist.
# Build the same reduced wheel on every arch so install paths stay identical.
_lingua_rs_commit="77e94d1a2a8e49bed873a7c502bcb51ba803ef0f"
_maturin_version="1.11.5"
_psycopg_c_version="3.3.4"

# Pacstall calls hooks with no args; dpkg argv is available at top-level when embedded.
_DPKG_ARGV=("$@")

source=(
  "${pkgname}-${pkgver}.tar.gz::https://github.com/wger-project/wger/archive/refs/tags/${pkgver}.tar.gz"
  "0001-psycopg-drop-binary-extra.patch"
  "wger.env.in"
  "wger.config.in"
  "wger.service"
  "wger-celery-worker.service"
  "wger-celery-beat.service"
  "wger.tmpfiles"
)

makedepends+=(
  "python3" "python3-venv" "python3-dev" "python3-pip"
  "build-essential" "pkg-config" "patch"
  "libpq-dev" "zlib1g-dev" "libjpeg62-turbo-dev" "libwebp-dev"
  "libssl-dev" "libffi-dev"
  "gettext" "curl" "ca-certificates" "tzdata" "git"
  "nodejs" "npm"
  "rustc" "cargo"
)

depends+=(
  "python3" "gunicorn"
  "libpq5" "libjpeg62-turbo" "libwebp7" "gettext-base" "tzdata"
  "postgresql" "dbconfig-pgsql" "debconf" "debconf-utils"
)

recommends=("valkey-server")
backup=('etc/wger/wger.env')

prepare() {
  set -e
  cd "${srcdir}/${_src}"
  for p in "${srcdir}"/*.patch; do
    patch -p1 --forward -i "${p}"
  done
}

build() {
  set -e
  local staging="${srcdir}/staging"
  local src_dest="${staging}${_install_prefix}/src"
  local venv="${staging}${_install_prefix}/venv"

  mkdir -p "${src_dest}"
  cp -a "${srcdir}/${_src}/." "${src_dest}/"

  npm install -g --silent sass
  (
    cd "${src_dest}"
    npm install --silent
    npm run --silent build:css:sass
  )

  "${_python}" -m venv "${venv}"
  "${venv}/bin/pip" install -q --no-cache-dir --upgrade pip setuptools wheel

  export CFLAGS_armv7_unknown_linux_gnueabihf="-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard"

  local lingua_src lingua_wheels maturin_venv
  lingua_src="$(mktemp -d)"
  lingua_wheels="$(mktemp -d)"
  maturin_venv="$(mktemp -d)"
  curl -fsSL "https://github.com/pemistahl/lingua-rs/archive/${_lingua_rs_commit}.tar.gz" \
    -o /tmp/lingua-rs.tar.gz
  tar xf /tmp/lingua-rs.tar.gz -C "${lingua_src}" --strip-components=1
  rm -f /tmp/lingua-rs.tar.gz
  "${_python}" -m venv "${maturin_venv}"
  "${maturin_venv}/bin/pip" install -q --no-cache-dir "maturin==${_maturin_version}"
  (
    cd "${lingua_src}"
    "${maturin_venv}/bin/maturin" build --release \
      --interpreter "$(command -v python3)" \
      --no-default-features \
      --features pyo3/extension-module,pyo3/generate-import-lib,python,english,spanish,catalan \
      --out "${lingua_wheels}"
  )
  "${venv}/bin/pip" install -q --no-cache-dir "${lingua_wheels}"/lingua_language_detector-*.whl
  rm -rf "${lingua_src}" "${lingua_wheels}" "${maturin_venv}"

  "${venv}/bin/pip" install -q --no-cache-dir --no-binary psycopg-c \
    "psycopg[c]==${_psycopg_c_version}"

  "${venv}/bin/pip" install -q --no-cache-dir "${src_dest}"

  (
    cd "${src_dest}/wger"
    "${venv}/bin/django-admin" compilemessages
  )

  sed -i "s|${staging}||g" "${venv}/pyvenv.cfg"
  find "${venv}/bin" -type f -exec sed -i "s|${staging}||g" {} +

  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel,pkg_resources} 2>/dev/null || true
  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel}-*.dist-info 2>/dev/null || true
  find "${venv}" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
  find "${venv}" -name "*.pyc" -delete 2>/dev/null || true
  find "${venv}" -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true

  local site_pkgs
  site_pkgs="$(echo "${venv}/lib"/python*/site-packages)"
  find "${site_pkgs}" -maxdepth 3 -type d \( -name tests -o -name test \) \
    -not -path "*/django/*" \
    -not -path "*/celery/*" \
    -exec rm -rf {} + 2>/dev/null || true

  find "${src_dest}" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
}

_render_in() {
  sed -e "s|@WGER_DOMAIN@|${_wger_domain}|g" \
      -e "s|@pkgver@|${pkgver}|g" \
      -e "s|@WGER_DB_NAME@|${_wger_db_name}|g" \
      -e "s|@WGER_DB_USER@|${_wger_db_user}|g" \
      -e "s|@WGER_DB_HOST@|${_wger_db_host}|g" \
      -e "s|@WGER_HTTP_PORT@|${_wger_http_port}|g" \
      "${1}" > "${2}"
}

package() {
  local staging="${srcdir}/staging"
  mkdir -p "${pkgdir}${_install_prefix}"
  cp -a "${staging}${_install_prefix}/." "${pkgdir}${_install_prefix}/"

  mkdir -p "${pkgdir}/etc/wger"
  _render_in "${srcdir}/wger.env.in" \
    "${pkgdir}/etc/wger/wger.env"

  install -Dm644 "${srcdir}/wger.service" \
    "${pkgdir}/usr/lib/systemd/system/wger.service"
  install -Dm644 "${srcdir}/wger-celery-worker.service" \
    "${pkgdir}/usr/lib/systemd/system/wger-celery-worker.service"
  install -Dm644 "${srcdir}/wger-celery-beat.service" \
    "${pkgdir}/usr/lib/systemd/system/wger-celery-beat.service"

  install -Dm644 "${srcdir}/wger.tmpfiles" \
    "${pkgdir}/usr/lib/tmpfiles.d/wger.conf"

  mkdir -p "${pkgdir}/var/lib/wger/media" "${pkgdir}/var/lib/wger/static" "${pkgdir}/var/log/wger"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/wger/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/wger/install/pgsql"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/wger.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

ensure_pg_role_db() {
  local role="$1"
  local dbname="$2"
  local pass="${3:-}"
  if runuser -u postgres -- psql -tc \
      "SELECT 1 FROM pg_roles WHERE rolname='${role}'" | grep -q 1; then
    if [ -n "${pass}" ]; then
      runuser -u postgres -- psql -c \
        "ALTER ROLE ${role} WITH LOGIN PASSWORD '${pass}';" 2>/dev/null || true
    else
      runuser -u postgres -- psql -c \
        "ALTER ROLE ${role} WITH LOGIN;" 2>/dev/null || true
    fi
  elif [ -n "${pass}" ]; then
    runuser -u postgres -- psql -c \
      "CREATE ROLE ${role} WITH LOGIN PASSWORD '${pass}';"
  else
    runuser -u postgres -- psql -c \
      "CREATE ROLE ${role} WITH LOGIN;"
  fi
  runuser -u postgres -- psql -tc \
    "SELECT 1 FROM pg_database WHERE datname='${dbname}'" | grep -q 1 \
    || runuser -u postgres -- createdb -O "${role}" "${dbname}"
}

post_install() {
  set -e
  if [ "$#" -eq 0 ] && [ "${#_DPKG_ARGV[@]}" -gt 0 ]; then
    set -- "${_DPKG_ARGV[@]}"
  elif [ "$#" -eq 0 ]; then
    set -- configure
  fi

  local src="/opt/wger/src"
  local venv="/opt/wger/venv"
  local env_file="/etc/wger/wger.env"
  local pkg="wger"

  . /usr/share/debconf/confmodule

  if ! id -u wger &>/dev/null; then
    adduser --system --group --home /var/lib/wger \
      --no-create-home --shell /bin/bash wger
  fi

  mkdir -p /var/lib/wger/media /var/lib/wger/static
  chown -R wger:wger /var/lib/wger /var/log/wger

  run_as_wger() {
    runuser -u wger -- bash -c '
      set -a; source "$1"; set +a
      cd "$2" || exit 1
      shift 2
      exec "$@"
    ' bash "$env_file" "$src" "$@"
  }

  if grep -q '__SECRETKEY_PLACEHOLDER__' "$env_file"; then
    local secret
    secret=$("$venv/bin/python" -c "import secrets; print(secrets.token_urlsafe(50))")
    sed -i "s|__SECRETKEY_PLACEHOLDER__|${secret}|" "$env_file"
  fi

  if grep -q '__JWTPRIVATE_PLACEHOLDER__' "$env_file"; then
    local jwt_output jwt_private jwt_public
    jwt_output=$(env DJANGO_SETTINGS_MODULE=settings.main PYTHONPATH="${src}" \
      "${venv}/bin/django-admin" generate-jwt-keys 2>/dev/null) || true
    jwt_private=$(printf '%s\n' "${jwt_output}" | grep '^JWT_PRIVATE_KEY=' | cut -d= -f2-)
    jwt_public=$(printf '%s\n' "${jwt_output}" | grep '^JWT_PUBLIC_KEY=' | cut -d= -f2-)
    if [ -n "${jwt_private}" ] && [ -n "${jwt_public}" ]; then
      sed -i "s|__JWTPRIVATE_PLACEHOLDER__|${jwt_private}|" "$env_file"
      sed -i "s|__JWTPUBLIC_PLACEHOLDER__|${jwt_public}|" "$env_file"
    else
      fancy_message error "Failed to generate JWT keys; placeholders left in ${env_file}."
    fi
  fi

  . /usr/share/dbconfig-common/dpkg/postinst.pgsql
  dbc_go "$pkg" "$@"

  # shellcheck disable=SC1091
  . /etc/dbconfig-common/${pkg}.conf

  write_db_env() {
    local use_password="$1"
    grep -vE '^(DJANGO_DB_DATABASE|DJANGO_DB_USER|DJANGO_DB_PASSWORD|DJANGO_DB_HOST|DJANGO_DB_PORT)=' \
      "$env_file" > "${env_file}.tmp"
    {
      cat "${env_file}.tmp"
      echo "DJANGO_DB_DATABASE=${dbc_dbname}"
      echo "DJANGO_DB_USER=${dbc_dbuser}"
      if [ "${use_password}" = "1" ]; then
        echo "DJANGO_DB_PASSWORD=${dbc_dbpass}"
        echo "DJANGO_DB_HOST=${db_host}"
        echo "DJANGO_DB_PORT=${dbc_dbport:-5432}"
      else
        echo "DJANGO_DB_HOST=${db_host}"
        echo "DJANGO_DB_PORT=${dbc_dbport:-5432}"
      fi
    } > "$env_file"
    rm -f "${env_file}.tmp"
  }

  local db_host="${dbc_dbserver:-127.0.0.1}"
  case "$db_host" in local|localhost) db_host="127.0.0.1" ;; esac

  local use_pw=1
  if [ "${dbc_install}" != "true" ]; then
    dbc_dbname="${dbc_dbname:-wger}"
    dbc_dbuser="${dbc_dbuser:-wger}"
    use_pw=0
  else
    case "${dbc_authmethod_user}:${dbc_dbserver:-local}" in
      ident:local|ident:|ident:localhost|ident:127.0.0.1) use_pw=0 ;;
    esac
  fi

  if [ "${use_pw}" = "1" ]; then
    ensure_pg_role_db "${dbc_dbuser}" "${dbc_dbname}" "${dbc_dbpass}"
  else
    ensure_pg_role_db "${dbc_dbuser}" "${dbc_dbname}"
  fi
  write_db_env "${use_pw}"

  chmod 640 "$env_file"
  chown root:wger "$env_file"

  run_as_wger "${venv}/bin/wger" bootstrap --no-process-static
  run_as_wger "${venv}/bin/django-admin" migrate --noinput
  run_as_wger "${venv}/bin/django-admin" collectstatic --noinput
  run_as_wger "${venv}/bin/django-admin" set-site-url || true

  fancy_message warn "Default admin (first install only): admin / adminadmin — CHANGE THIS PASSWORD immediately."

  chmod 750 /var/lib/wger
  chmod -R g+rX /var/lib/wger/static 2>/dev/null || true

  systemd-tmpfiles --create /usr/lib/tmpfiles.d/wger.conf 2>/dev/null || true
  systemctl daemon-reload
  systemctl enable --now wger

  db_stop
}

pre_remove() {
  if [ "$#" -eq 0 ] && [ "${#_DPKG_ARGV[@]}" -gt 0 ]; then
    set -- "${_DPKG_ARGV[@]}"
  elif [ "$#" -eq 0 ]; then
    set -- remove
  fi

  if [ -f /usr/share/dbconfig-common/dpkg/prerm.pgsql ]; then
    . /usr/share/debconf/confmodule
    . /usr/share/dbconfig-common/dpkg/prerm.pgsql
    dbc_go wger "$@"
  fi
  systemctl stop wger wger-celery-worker wger-celery-beat 2>/dev/null || true
  systemctl disable wger wger-celery-worker wger-celery-beat 2>/dev/null || true
}

post_remove() {
  if [ "$#" -eq 0 ] && [ "${#_DPKG_ARGV[@]}" -gt 0 ]; then
    set -- "${_DPKG_ARGV[@]}"
  elif [ "$#" -eq 0 ]; then
    set -- remove
  fi

  if [ -f /usr/share/dbconfig-common/dpkg/postrm.pgsql ]; then
    . /usr/share/debconf/confmodule
    . /usr/share/dbconfig-common/dpkg/postrm.pgsql
    dbc_go wger "$@"
  fi
}
