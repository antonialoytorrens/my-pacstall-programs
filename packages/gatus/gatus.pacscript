pkgbase="gatus"
pkgname=("gatus" "gatus-pgsql" "gatus-sqlite")
pkgver="5.36.0"
pkgrel="3"
arch=('amd64' 'arm64' 'armhf')
url="https://gatus.io/"
license=('Apache-2.0')
pkgdesc="Automated developer-oriented status page (native systemd)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/gatus-deb>")
external_connection=true

_gatus_http_port="38427"
_gatus_db_name="gatus"
_gatus_db_user="gatus"

# Pacstall calls hooks with no args; dpkg argv is available at top-level when embedded.
_DPKG_ARGV=("$@")

source=(
  "https://github.com/TwiN/gatus/archive/refs/tags/v${pkgver}.tar.gz"
  "gatus.service"
  "00-main.yaml.in"
  "gatus-pgsql.config.in"
  "gatus-sqlite.config.in"
  "pgsql.conf"
)

makedepends+=(
  "ca-certificates" "curl" "git"
)

# Go: official toolchain in the Dockerfile (amd64/arm64/armv6l for armhf).
# Same build line everywhere — CGO_ENABLED=0 (sqlite via modernc.org).

build() {
  set -e
  export CGO_ENABLED=0
  export PATH="/usr/local/go/bin:${PATH}"
  export GOCACHE="${srcdir}/.gocache"
  export GOMODCACHE="${srcdir}/.gomodcache"

  cd "${srcdir}/gatus-${pkgver}"
  go build -trimpath -ldflags="-s -w" -o gatus .
}

_render_in() {
  sed -e "s|@GATUS_HTTP_PORT@|${_gatus_http_port}|g" \
      -e "s|@GATUS_DB_NAME@|${_gatus_db_name}|g" \
      -e "s|@GATUS_DB_USER@|${_gatus_db_user}|g" \
      "${1}" > "${2}"
}

package_gatus() {
  depends=("ca-certificates" "systemd" "gatus-pgsql | gatus-sqlite | dbconfig-no-thanks")
  backup=('etc/gatus/config.d/00-main.yaml')
  pkgdesc="Automated developer-oriented status page (native systemd)"

  install -Dm755 "${srcdir}/gatus-${pkgver}/gatus" \
    "${pkgdir}/usr/bin/gatus"

  mkdir -p "${pkgdir}/etc/gatus/config.d"
  _render_in "${srcdir}/00-main.yaml.in" \
    "${pkgdir}/etc/gatus/config.d/00-main.yaml"

  install -Dm644 "${srcdir}/gatus.service" \
    "${pkgdir}/usr/lib/systemd/system/gatus.service"

  mkdir -p "${pkgdir}/var/lib/gatus"
}

package_gatus-pgsql() {
  arch=('all')
  depends=("gatus" "dbconfig-pgsql" "postgresql" "debconf" "debconf-utils" "python3")
  conflicts=("gatus-sqlite")
  replaces=("gatus-sqlite")
  breaks=("gatus-sqlite")
  provides=("gatus-db")
  pkgdesc="Gatus PostgreSQL storage (dbconfig-pgsql)"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/gatus-pgsql/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/gatus-pgsql/install/pgsql"

  install -Dm644 "${srcdir}/pgsql.conf" \
    "${pkgdir}/usr/lib/systemd/system/gatus.service.d/pgsql.conf"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/gatus-pgsql.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

package_gatus-sqlite() {
  arch=('all')
  depends=("gatus" "dbconfig-sqlite3" "debconf" "debconf-utils")
  conflicts=("gatus-pgsql")
  replaces=("gatus-pgsql")
  breaks=("gatus-pgsql")
  provides=("gatus-db")
  pkgdesc="Gatus SQLite storage (dbconfig-sqlite3)"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/gatus-sqlite/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/gatus-sqlite/install/sqlite3"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/gatus-sqlite.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

_gatus_ensure_user() {
  if ! getent group gatus >/dev/null; then
    groupadd --system gatus
  fi
  if ! getent passwd gatus >/dev/null; then
    useradd --system --gid gatus --home-dir /var/lib/gatus \
      --shell /usr/sbin/nologin gatus
  fi
  mkdir -p /var/lib/gatus /etc/gatus/config.d
  chown gatus:gatus /var/lib/gatus
  chmod 750 /var/lib/gatus
  chown root:gatus /etc/gatus /etc/gatus/config.d
  chmod 750 /etc/gatus /etc/gatus/config.d
  if [ -f /etc/gatus/config.d/00-main.yaml ]; then
    chown root:gatus /etc/gatus/config.d/00-main.yaml
    chmod 640 /etc/gatus/config.d/00-main.yaml
  fi
}

_gatus_write_storage_yaml() {
  local type="$1"
  local path="$2"
  local out="/etc/gatus/config.d/10-storage.yaml"
  cat > "${out}" << EOF
storage:
  type: ${type}
  path: "${path}"
EOF
  chown root:gatus "${out}"
  chmod 640 "${out}"
}

_gatus_restart() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl try-restart gatus.service 2>/dev/null || true
  fi
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

  local pkg="${DPKG_MAINTSCRIPT_PACKAGE:-}"

  case "${pkg}" in
    gatus)
      _gatus_ensure_user
      if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload || true
        systemctl enable gatus.service || true
        systemctl start gatus.service || true
      fi
      ;;

    gatus-pgsql)
      _gatus_ensure_user
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postinst.pgsql
      dbc_go gatus-pgsql "$@"

      # shellcheck disable=SC1091
      . /etc/dbconfig-common/gatus-pgsql.conf

      local db_host="${dbc_dbserver:-127.0.0.1}"
      case "$db_host" in local|localhost) db_host="127.0.0.1" ;; esac
      local storage_path=""

      local use_pw=1
      if [ "${dbc_install}" != "true" ]; then
        dbc_dbname="${dbc_dbname:-gatus}"
        dbc_dbuser="${dbc_dbuser:-gatus}"
        use_pw=0
      else
        case "${dbc_authmethod_user}:${dbc_dbserver:-local}" in
          ident:local|ident:|ident:localhost|ident:127.0.0.1) use_pw=0 ;;
        esac
      fi

      if [ "${use_pw}" = "1" ]; then
        ensure_pg_role_db "${dbc_dbuser}" "${dbc_dbname}" "${dbc_dbpass}"
        local enc_pass
        enc_pass="$(printf '%s' "${dbc_dbpass}" | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))')"
        storage_path="postgres://${dbc_dbuser}:${enc_pass}@${db_host}:${dbc_dbport:-5432}/${dbc_dbname}?sslmode=disable"
      else
        ensure_pg_role_db "${dbc_dbuser}" "${dbc_dbname}"
        storage_path="postgres://${dbc_dbuser}@/${dbc_dbname}?host=/var/run/postgresql"
      fi

      _gatus_write_storage_yaml postgres "${storage_path}"
      db_stop 2>/dev/null || true
      _gatus_restart
      ;;

    gatus-sqlite)
      _gatus_ensure_user
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postinst.sqlite3
      dbc_go gatus-sqlite "$@"

      local sqlite_path="/var/lib/gatus/data.db"
      _gatus_write_storage_yaml sqlite "${sqlite_path}"
      chown gatus:gatus /var/lib/gatus
      db_stop 2>/dev/null || true
      _gatus_restart
      ;;
  esac
}

pre_remove() {
  if [ "$#" -eq 0 ] && [ "${#_DPKG_ARGV[@]}" -gt 0 ]; then
    set -- "${_DPKG_ARGV[@]}"
  elif [ "$#" -eq 0 ]; then
    set -- remove
  fi

  local pkg="${DPKG_MAINTSCRIPT_PACKAGE:-}"
  case "${pkg}" in
    gatus)
      if command -v systemctl >/dev/null 2>&1; then
        systemctl stop gatus.service 2>/dev/null || true
        systemctl disable gatus.service 2>/dev/null || true
      fi
      ;;
    gatus-pgsql)
      if [ -f /usr/share/dbconfig-common/dpkg/prerm.pgsql ]; then
        . /usr/share/debconf/confmodule
        . /usr/share/dbconfig-common/dpkg/prerm.pgsql
        dbc_go gatus-pgsql "$@"
      fi
      rm -f /etc/gatus/config.d/10-storage.yaml
      ;;
    gatus-sqlite)
      if [ -f /usr/share/dbconfig-common/dpkg/prerm.sqlite3 ]; then
        . /usr/share/debconf/confmodule
        . /usr/share/dbconfig-common/dpkg/prerm.sqlite3
        dbc_go gatus-sqlite "$@"
      fi
      rm -f /etc/gatus/config.d/10-storage.yaml
      ;;
  esac
}

post_remove() {
  if [ "$#" -eq 0 ] && [ "${#_DPKG_ARGV[@]}" -gt 0 ]; then
    set -- "${_DPKG_ARGV[@]}"
  elif [ "$#" -eq 0 ]; then
    set -- remove
  fi

  local pkg="${DPKG_MAINTSCRIPT_PACKAGE:-}"
  case "${pkg}" in
    gatus)
      if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload || true
      fi
      ;;
    gatus-pgsql)
      if [ -f /usr/share/dbconfig-common/dpkg/postrm.pgsql ]; then
        . /usr/share/debconf/confmodule
        . /usr/share/dbconfig-common/dpkg/postrm.pgsql
        dbc_go gatus-pgsql "$@"
      fi
      ;;
    gatus-sqlite)
      if [ -f /usr/share/dbconfig-common/dpkg/postrm.sqlite3 ]; then
        . /usr/share/debconf/confmodule
        . /usr/share/dbconfig-common/dpkg/postrm.sqlite3
        dbc_go gatus-sqlite "$@"
      fi
      ;;
  esac
}
