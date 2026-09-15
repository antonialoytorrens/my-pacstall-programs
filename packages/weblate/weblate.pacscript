pkgname="weblate"
pkgver="2026.9.1"
pkgrel="1"
arch=('amd64' 'arm64' 'armhf')
url="https://weblate.org/"
license=('GPL-3.0-or-later')
pkgdesc="Weblate continuous localization (native systemd, bundled venv, dbconfig-pgsql)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/weblate-deb>")
external_connection=true

_weblate_domain="weblate.localhost.local"
_weblate_db_name="weblate"
_weblate_db_user="weblate"
_weblate_http_port="38447"
_install_prefix="/opt/weblate"
_psycopg_c_ver="3.3.4"

# Pacstall calls hooks with no args; dpkg argv is available at top-level when embedded.
_DPKG_ARGV=("$@")

source=(
  "https://files.pythonhosted.org/packages/41/fa/d8025e1120dfbb44eb4783d6d41418070af7bbff09a2fd1db3b88f542c18/weblate-${pkgver}.tar.gz"
  "weblate.env.in"
  "weblate_settings.py.in"
  "weblate.config.in"
  "weblate-web.service"
  "weblate-celery.service"
  "weblate.tmpfiles"
)

makedepends_trixie=(
  "python3.13" "python3.13-venv" "python3.13-dev"
)

makedepends_resolute=(
  "python3" "python3-venv" "python3-dev"
)

makedepends+=(
  "build-essential" "pkg-config" "cmake"
  "libpq-dev" "libxml2-dev" "libxslt1-dev" "libffi-dev"
  "libcairo2-dev"
  "libgirepository-2.0-dev" "gir1.2-girepository-2.0-dev"
  "gir1.2-pango-1.0" "gir1.2-harfbuzz-0.0" "gir1.2-rsvg-2.0"
  "libacl1-dev" "liblz4-dev" "libzstd-dev"
  "libjpeg-dev" "zlib1g-dev"
  "tesseract-ocr" "libtesseract-dev" "libleptonica-dev"
  "curl" "ca-certificates" "tzdata" "git"
  "rustc" "cargo"
)

depends_trixie=(
  "python3.13" "libxml2" "libjpeg62-turbo"
)

depends_resolute=(
  "python3" "libxml2-16" "libjpeg-turbo8"
)

depends+=(
  "libpq5" "libxslt1.1" "libcairo2"
  "libgirepository-2.0-0" "gir1.2-pango-1.0" "gir1.2-rsvg-2.0"
  "libacl1" "liblz4-1" "libzstd1" "zlib1g"
  "libtesseract5" "tesseract-ocr"
  "postgresql" "valkey-server" "openssh-client" "git"
  "dbconfig-pgsql" "debconf" "debconf-utils"
)

backup=('etc/weblate/weblate.env' 'etc/weblate/weblate_settings.py')

build() {
  set -e
  # cc-rs on armhf: crates that force -march drop GCC's default -mfpu → "lacks an FPU".
  export CFLAGS_armv7_unknown_linux_gnueabihf="-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard"

  local staging="${srcdir}/staging"
  local venv="${staging}${_install_prefix}/venv"
  mkdir -p "${venv}"
  python3 -m venv "${venv}"
  "${venv}/bin/pip" install -q --no-cache-dir --upgrade pip setuptools wheel

  "${venv}/bin/pip" install -q --no-cache-dir --no-binary psycopg-c \
    "psycopg[c]==${_psycopg_c_ver}"

  "${venv}/bin/pip" install -q --no-cache-dir \
    "${srcdir}/weblate-${pkgver}" gunicorn

  sed -i "s|${staging}||g" "${venv}/pyvenv.cfg"
  find "${venv}/bin" -type f -exec sed -i "s|${staging}||g" {} +

  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel,pkg_resources}
  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel}-*.dist-info
  find "${venv}" -depth -type d -name __pycache__ -exec rm -rf {} +
  find "${venv}" -name "*.pyc" -delete

  local site_pkgs
  site_pkgs="$(echo "${venv}/lib"/python*/site-packages)"
  find "${site_pkgs}" -depth -maxdepth 3 -type d \( -name tests -o -name test \) \
    -not -path "*/django/*" \
    -not -path "*/celery/*" \
    -not -path "*/social_core/*" \
    -not -path "*/social_django/*" \
    -exec rm -rf {} +

  find "${venv}" -name "*.so" -exec strip --strip-unneeded {} +
}

_render_in() {
  sed -e "s|@WEBLATE_DOMAIN@|${_weblate_domain}|g" \
      -e "s|@pkgver@|${pkgver}|g" \
      -e "s|@WEBLATE_DB_NAME@|${_weblate_db_name}|g" \
      -e "s|@WEBLATE_DB_USER@|${_weblate_db_user}|g" \
      -e "s|@WEBLATE_HTTP_PORT@|${_weblate_http_port}|g" \
      "${1}" > "${2}"
}

package() {
  local staging="${srcdir}/staging"
  mkdir -p "${pkgdir}${_install_prefix}"
  cp -a "${staging}${_install_prefix}/." "${pkgdir}${_install_prefix}/"

  mkdir -p "${pkgdir}/etc/weblate"
  _render_in "${srcdir}/weblate.env.in" \
    "${pkgdir}/etc/weblate/weblate.env"
  _render_in "${srcdir}/weblate_settings.py.in" \
    "${pkgdir}/etc/weblate/weblate_settings.py"

  install -Dm644 "${srcdir}/weblate-web.service" \
    "${pkgdir}/usr/lib/systemd/system/weblate-web.service"
  install -Dm644 "${srcdir}/weblate-celery.service" \
    "${pkgdir}/usr/lib/systemd/system/weblate-celery.service"

  install -Dm644 "${srcdir}/weblate.tmpfiles" \
    "${pkgdir}/usr/lib/tmpfiles.d/weblate.conf"

  mkdir -p "${pkgdir}/var/lib/weblate" "${pkgdir}/var/cache/weblate" "${pkgdir}/var/log/weblate"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/weblate/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/weblate/install/pgsql"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/weblate.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

ensure_pg_role_db() {
  local role="$1" dbname="$2" pass="${3:-}"
  if [ -n "$pass" ]; then
    runuser -u postgres -- psql -c \
      "DO \$\$ BEGIN CREATE ROLE ${role} WITH LOGIN PASSWORD '${pass}'; EXCEPTION WHEN duplicate_object THEN ALTER ROLE ${role} WITH LOGIN PASSWORD '${pass}'; END \$\$;"
  else
    runuser -u postgres -- psql -c \
      "DO \$\$ BEGIN CREATE ROLE ${role} WITH LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;"
  fi
  runuser -u postgres -- psql -tc \
    "SELECT 1 FROM pg_database WHERE datname='${dbname}'" | grep -q 1 \
    || runuser -u postgres -- createdb -O "${role}" "${dbname}"
}

_shell_quote() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

post_install() {
  set -e
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- configure

  local venv="/opt/weblate/venv"
  local env_file="/etc/weblate/weblate.env"
  local settings="/etc/weblate/weblate_settings.py"
  local pkg="weblate"
  local weblate_bin="${venv}/bin/weblate"

  . /usr/share/debconf/confmodule

  if ! id -u weblate &>/dev/null; then
    adduser --system --group --home /var/lib/weblate \
      --no-create-home --shell /bin/bash weblate
  fi

  mkdir -p /var/lib/weblate /var/cache/weblate /var/log/weblate
  chown -R weblate:weblate /var/lib/weblate /var/cache/weblate /var/log/weblate

  if [ ! -e /home/weblate ]; then
    ln -s /var/lib/weblate /home/weblate
  fi

  run_as_weblate() {
    runuser -u weblate -- bash -c '
      set -a; source "$1"; set +a
      export DJANGO_SETTINGS_MODULE=weblate_settings
      export PYTHONPATH="/etc/weblate${PYTHONPATH:+:$PYTHONPATH}"
      shift
      exec "$@"
    ' bash "$env_file" "$@"
  }

  # Alphanumeric only — safe for bash source and systemd EnvironmentFile.
  if grep -q '__SECRETKEY_PLACEHOLDER__' "$env_file"; then
    local secret
    secret=$("${venv}/bin/python" -c "import secrets; print(secrets.token_hex(32))")
    sed -i "s|__SECRETKEY_PLACEHOLDER__|${secret}|" "$env_file"
  fi

  . /usr/share/dbconfig-common/dpkg/postinst.pgsql
  dbc_go "$pkg" "$@"

  # shellcheck disable=SC1091
  . /etc/dbconfig-common/${pkg}.conf

  write_db_env() {
    local use_password="$1"
    grep -vE '^(WEBLATE_DB_NAME|WEBLATE_DB_USER|WEBLATE_DB_PASSWORD|WEBLATE_DB_HOST|WEBLATE_DB_PORT)=' \
      "$env_file" > "${env_file}.tmp"
    {
      cat "${env_file}.tmp"
      echo "WEBLATE_DB_NAME='$(_shell_quote "${dbc_dbname}")'"
      echo "WEBLATE_DB_USER='$(_shell_quote "${dbc_dbuser}")'"
      if [ "${use_password}" = "1" ]; then
        echo "WEBLATE_DB_PASSWORD='$(_shell_quote "${dbc_dbpass}")'"
        echo "WEBLATE_DB_HOST='$(_shell_quote "${db_host}")'"
        echo "WEBLATE_DB_PORT='$(_shell_quote "${dbc_dbport:-5432}")'"
      else
        echo "WEBLATE_DB_PASSWORD="
        echo "WEBLATE_DB_HOST="
        echo "WEBLATE_DB_PORT="
      fi
    } > "$env_file"
    rm -f "${env_file}.tmp"
  }

  local db_host="${dbc_dbserver:-127.0.0.1}"
  case "$db_host" in local|localhost) db_host="127.0.0.1" ;; esac

  local use_pw=1
  if [ "${dbc_install}" != "true" ]; then
    dbc_dbname="${dbc_dbname:-weblate}"
    dbc_dbuser="${dbc_dbuser:-weblate}"
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

  chmod 640 "$env_file" "$settings"
  chown root:weblate "$env_file" "$settings"

  run_as_weblate "$weblate_bin" migrate --noinput
  run_as_weblate "$weblate_bin" collectstatic --noinput --clear
  run_as_weblate "$weblate_bin" compress --force

  # No default admin — registration is open; first user signs up in the UI.

  # DATA_DIR stays private; nginx (www-data) needs group traverse + read for STATIC_ROOT.
  chmod 750 /var/lib/weblate
  mkdir -p /var/lib/weblate/static
  chmod 750 /var/lib/weblate/static
  chown -R weblate:weblate /var/lib/weblate/static
  if id -u www-data &>/dev/null; then
    usermod -aG weblate www-data
  fi

  systemd-tmpfiles --create /usr/lib/tmpfiles.d/weblate.conf

  systemctl daemon-reload
  systemctl enable --now weblate-web weblate-celery

  db_stop
}

pre_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  . /usr/share/debconf/confmodule
  . /usr/share/dbconfig-common/dpkg/prerm.pgsql
  dbc_go weblate "$@"
  systemctl stop weblate-web weblate-celery
  systemctl disable weblate-web weblate-celery
}

post_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  . /usr/share/debconf/confmodule
  . /usr/share/dbconfig-common/dpkg/postrm.pgsql
  dbc_go weblate "$@"

  if [ "$1" = "purge" ]; then
    if [ -L /home/weblate ]; then
      case "$(readlink /home/weblate)" in
        /var/lib/weblate) rm -f /home/weblate ;;
      esac
    fi
    rm -rf /opt/weblate
    rm -rf /var/log/weblate /var/cache/weblate /var/lib/weblate
  fi
}
