pkgname="glitchtip"
pkgver="6.2.6"
pkgrel="8"
arch=('amd64')
url="https://glitchtip.com/"
license=('MIT')
pkgdesc="GlitchTip error tracking (trimmed profile, native systemd, bundled venv)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/glitchtip-deb>")
external_connection=true

_glitchtip_domain="glitchtip.localhost.local"
_glitchtip_db_name="glitchtip"
_glitchtip_db_user="glitchtip"
_glitchtip_db_host="127.0.0.1"
_glitchtip_http_port="38417"

_backend="glitchtip-backend-v${pkgver}"
_frontend="glitchtip-frontend-v${pkgver}"
_frontend_assets="${_frontend}-assets.zip"
_install_prefix="/opt/glitchtip"
_python="python3.13"

# Pacstall calls hooks with no args; dpkg argv is available at top-level when embedded.
_DPKG_ARGV=("$@")

source=(
  "https://gitlab.com/glitchtip/glitchtip-backend/-/archive/v${pkgver}/${_backend}.tar.gz"
  "${_frontend_assets}::https://gitlab.com/api/v4/projects/15449363/jobs/artifacts/v${pkgver}/download?job=build-assets"
  "0001-trim-optional-deps.patch"
  "0002-local-filesystem-profile.patch"
  "0003-deb-database-components.patch"
  "glitchtip.env.in"
  "glitchtip.config.in"
  "glitchtip.service"
  "glitchtip-worker.service"
  "requirements.txt"
)

makedepends_trixie=(
  "python3.13" "python3.13-venv" "python3.13-dev"
)

makedepends+=(
  "build-essential" "pkg-config" "patch"
  "libpq-dev" "libxml2-dev" "zlib1g-dev" "libssl-dev" "libffi-dev"
  "curl" "ca-certificates" "tzdata" "git" "rustc" "cargo"
)

depends_trixie=(
  "python3.13"
)

depends+=(
  "libpq5" "libxml2" "postgresql" "valkey-server"
  "dbconfig-pgsql" "postgresql" "debconf" "debconf-utils"
)

recommends=("nginx")
backup=('etc/glitchtip/glitchtip.env')

prepare() {
  set -e
  cd "${srcdir}/${_backend}"
  for p in "${srcdir}"/*.patch; do
    patch -p1 --forward -i "${p}"
  done
}

_install_frontend_dist() {
  local dest="$1"
  local browser="${srcdir}/dist/glitchtip-frontend/browser"

  mkdir -p "${dest}"
  cp -a "${browser}/." "${dest}/"
  test -f "${dest}/index.html"
}

build() {
  set -e
  local staging="${srcdir}/staging"
  mkdir -p "${staging}${_install_prefix}/src"
  cp -a "${srcdir}/${_backend}/." "${staging}${_install_prefix}/src/"

  _install_frontend_dist "${staging}${_install_prefix}/src/dist"

  local venv="${staging}${_install_prefix}/venv"
  "${_python}" -m venv "${venv}"
  "${venv}/bin/pip" install -q --no-cache-dir --upgrade pip
  "${venv}/bin/pip" install -q --no-cache-dir --require-hashes \
    -r "${srcdir}/requirements.txt"
  "${venv}/bin/pip" install -q --no-cache-dir --no-deps \
    "${staging}${_install_prefix}/src"

  sed -i "s|${staging}||g" "${venv}/pyvenv.cfg"
  find "${venv}/bin" -type f -exec sed -i "s|${staging}||g" {} +

  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel,pkg_resources} 2>/dev/null || true
  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel}-*.dist-info 2>/dev/null || true
  find "${venv}" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
  find "${venv}" -name "*.pyc" -delete 2>/dev/null || true
  find "${venv}" -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true
  find "${staging}${_install_prefix}/src" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
}

_render_in() {
  sed -e "s|@GLITCHTIP_DOMAIN@|${_glitchtip_domain}|g" \
      -e "s|@pkgver@|${pkgver}|g" \
      -e "s|@GLITCHTIP_HTTP_PORT@|${_glitchtip_http_port}|g" \
      -e "s|@GLITCHTIP_DB_NAME@|${_glitchtip_db_name}|g" \
      -e "s|@GLITCHTIP_DB_USER@|${_glitchtip_db_user}|g" \
      -e "s|@GLITCHTIP_DB_HOST@|${_glitchtip_db_host}|g" \
      "${1}" > "${2}"
}

package() {
  local staging="${srcdir}/staging"
  mkdir -p "${pkgdir}${_install_prefix}"
  cp -a "${staging}${_install_prefix}/." "${pkgdir}${_install_prefix}/"

  mkdir -p "${pkgdir}/etc/glitchtip"
  _render_in "${srcdir}/glitchtip.env.in" \
    "${pkgdir}/etc/glitchtip/glitchtip.env"

  install -Dm644 "${srcdir}/glitchtip.service" \
    "${pkgdir}/usr/lib/systemd/system/glitchtip.service"
  install -Dm644 "${srcdir}/glitchtip-worker.service" \
    "${pkgdir}/usr/lib/systemd/system/glitchtip-worker.service"

  mkdir -p "${pkgdir}/var/lib/glitchtip/uploads" "${pkgdir}/var/lib/glitchtip/static" "${pkgdir}/var/log/glitchtip"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/glitchtip/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/glitchtip/install/pgsql"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/glitchtip.config.in" "${pkgdir}/DEBIAN/config"
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

  local src="/opt/glitchtip/src"
  local venv="/opt/glitchtip/venv"
  local env_file="/etc/glitchtip/glitchtip.env"
  local pkg="glitchtip"

  . /usr/share/debconf/confmodule

  if ! id -u glitchtip &>/dev/null; then
    adduser --system --group --home /var/lib/glitchtip \
      --no-create-home --shell /usr/sbin/nologin glitchtip
  fi

  mkdir -p /var/lib/glitchtip/uploads /var/lib/glitchtip/static
  chown -R glitchtip:glitchtip /var/lib/glitchtip /var/log/glitchtip

  run_as_glitchtip() {
    runuser -u glitchtip -- bash -c '
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

  . /usr/share/dbconfig-common/dpkg/postinst.pgsql
  dbc_go "$pkg" "$@"

  # shellcheck disable=SC1091
  . /etc/dbconfig-common/${pkg}.conf

  write_db_env() {
    local use_password="$1"
    grep -vE '^(DATABASE_NAME|DATABASE_USER|DATABASE_PASSWORD|DATABASE_HOST|DATABASE_PORT)=' \
      "$env_file" > "${env_file}.tmp"
    {
      cat "${env_file}.tmp"
      echo "DATABASE_NAME=${dbc_dbname}"
      echo "DATABASE_USER=${dbc_dbuser}"
      if [ "${use_password}" = "1" ]; then
        echo "DATABASE_PASSWORD=${dbc_dbpass}"
        echo "DATABASE_HOST=${db_host}"
        echo "DATABASE_PORT=${dbc_dbport:-5432}"
      fi
    } > "$env_file"
    rm -f "${env_file}.tmp"
  }

  local db_host="${dbc_dbserver:-127.0.0.1}"
  case "$db_host" in local|localhost) db_host="127.0.0.1" ;; esac

  local use_pw=1
  if [ "${dbc_install}" != "true" ]; then
    dbc_dbname="${dbc_dbname:-glitchtip}"
    dbc_dbuser="${dbc_dbuser:-glitchtip}"
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
  chown root:glitchtip "$env_file"

  run_as_glitchtip "$venv/bin/python" "$src/manage.py" migrate --no-input
  run_as_glitchtip "$venv/bin/python" "$src/manage.py" maintain_partitions || true
  run_as_glitchtip "$venv/bin/python" "$src/manage.py" collectstatic --no-input

  chmod 750 /var/lib/glitchtip
  chmod -R g+rX /var/lib/glitchtip/static 2>/dev/null || true

  systemctl daemon-reload
  systemctl enable --now glitchtip glitchtip-worker

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
    dbc_go glitchtip "$@"
  fi
  systemctl stop glitchtip glitchtip-worker 2>/dev/null || true
  systemctl disable glitchtip glitchtip-worker 2>/dev/null || true
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
    dbc_go glitchtip "$@"
  fi
}
