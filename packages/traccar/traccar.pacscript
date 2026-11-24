pkgbase="traccar"
pkgname=("traccar" "traccar-web" "traccar-pgsql" "traccar-mysql")
pkgver="6.17.0"
pkgrel="1"
arch=('amd64' 'arm64')
url="https://www.traccar.org/"
license=('Apache-2.0')
pkgdesc="Traccar GPS tracking server (native systemd; use traccar-pgsql or traccar-mysql in production)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/my-pacstall-programs>")
external_connection=true

_traccar_db_name="traccar"
_traccar_db_user="traccar"
_traccar_web_path="/usr/share/traccar-web"
_traccar_localization_path="/opt/traccar/templates/translations"
_traccar_data_path="/var/lib/traccar/data"
_traccar_media_path="/var/lib/traccar/media"
_traccar_log_file="/var/lib/traccar/logs/tracker-server.log"
_install_prefix="/opt/traccar"

# Pacstall calls hooks with no args; dpkg argv is available at top-level when embedded.
_DPKG_ARGV=("$@")

source=(
  "https://github.com/traccar/traccar/archive/refs/tags/v${pkgver}.tar.gz"
  "traccar-other-${pkgver}.zip::https://github.com/traccar/traccar/releases/download/v${pkgver}/traccar-other-${pkgver}.zip"
  "traccar.service"
  "traccar.xml.in"
  "traccar-pgsql.config.in"
  "traccar-mysql.config.in"
  "pgsql.conf"
  "mysql.conf"
)

makedepends+=(
  "openjdk-21-jdk-headless" "ca-certificates" "curl" "unzip"
)

_render_in() {
  sed -e "s|@TRACCAR_DB_NAME@|${_traccar_db_name}|g" \
      -e "s|@TRACCAR_DB_USER@|${_traccar_db_user}|g" \
      -e "s|@TRACCAR_WEB_PATH@|${_traccar_web_path}|g" \
      -e "s|@TRACCAR_LOCALIZATION_PATH@|${_traccar_localization_path}|g" \
      -e "s|@TRACCAR_DATA_PATH@|${_traccar_data_path}|g" \
      -e "s|@TRACCAR_MEDIA_PATH@|${_traccar_media_path}|g" \
      -e "s|@TRACCAR_LOG_FILE@|${_traccar_log_file}|g" \
      "${1}" > "${2}"
}

_other_root() {
  # Pacstall may leave the release zip contents at srcdir or under a subdir.
  if [ -d "${srcdir}/web" ]; then
    echo "${srcdir}"
  elif [ -d "${srcdir}/traccar-other-${pkgver}/web" ]; then
    echo "${srcdir}/traccar-other-${pkgver}"
  else
    local found
    found="$(find "${srcdir}" -maxdepth 3 -type d -name web 2>/dev/null | head -n1)"
    if [ -n "${found}" ]; then
      dirname "${found}"
    else
      echo "ERROR: bundled traccar web/ not found under ${srcdir}" >&2
      return 1
    fi
  fi
}

build() {
  set -e
  cd "${srcdir}/traccar-${pkgver}"
  export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-$(dpkg --print-architecture)}"
  if [ ! -x "${JAVA_HOME}/bin/java" ]; then
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f /usr/bin/javac)")")"
  fi
  export PATH="${JAVA_HOME}/bin:${PATH}"
  ./gradlew assemble --no-daemon
  test -f target/tracker-server.jar
  test -d target/lib
}

package_traccar() {
  depends=(
    "openjdk-21-jre-headless" "systemd" "ca-certificates"
    "traccar-pgsql | traccar-mysql | dbconfig-no-thanks"
  )
  recommends=("traccar-web")
  backup=('etc/traccar/traccar.xml')
  pkgdesc="Traccar GPS tracking server (native systemd; use traccar-pgsql or traccar-mysql in production)"

  local src="${srcdir}/traccar-${pkgver}"
  local other
  other="$(_other_root)"

  install -Dm644 "${src}/target/tracker-server.jar" \
    "${pkgdir}${_install_prefix}/tracker-server.jar"

  mkdir -p "${pkgdir}${_install_prefix}/lib"
  cp -a "${src}/target/lib/." "${pkgdir}${_install_prefix}/lib/"

  mkdir -p "${pkgdir}${_install_prefix}/schema"
  cp -a "${src}/schema/." "${pkgdir}${_install_prefix}/schema/"

  mkdir -p "${pkgdir}${_install_prefix}/templates"
  cp -a "${src}/templates/." "${pkgdir}${_install_prefix}/templates/"
  if [ -d "${other}/templates/translations" ]; then
    mkdir -p "${pkgdir}${_install_prefix}/templates/translations"
    cp -a "${other}/templates/translations/." \
      "${pkgdir}${_install_prefix}/templates/translations/"
  fi

  mkdir -p "${pkgdir}/etc/traccar"
  _render_in "${srcdir}/traccar.xml.in" \
    "${pkgdir}/etc/traccar/traccar.xml"

  install -Dm644 "${srcdir}/traccar.service" \
    "${pkgdir}/usr/lib/systemd/system/traccar.service"

  mkdir -p \
    "${pkgdir}/var/lib/traccar/data" \
    "${pkgdir}/var/lib/traccar/logs" \
    "${pkgdir}/var/lib/traccar/media"
}

package_traccar-web() {
  arch=('all')
  pkgdesc="Traccar web UI (prebuilt assets from upstream server release)"
  depends=()

  local other
  other="$(_other_root)"
  mkdir -p "${pkgdir}${_traccar_web_path}"
  cp -a "${other}/web/." "${pkgdir}${_traccar_web_path}/"
  test -f "${pkgdir}${_traccar_web_path}/index.html"
}

package_traccar-pgsql() {
  arch=('all')
  depends=("traccar" "dbconfig-pgsql" "postgresql" "debconf" "debconf-utils" "python3")
  conflicts=("traccar-mysql")
  replaces=("traccar-mysql")
  breaks=("traccar-mysql")
  provides=("traccar-db")
  pkgdesc="Traccar PostgreSQL storage (dbconfig-pgsql)"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/traccar-pgsql/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/traccar-pgsql/install/pgsql"

  install -Dm644 "${srcdir}/pgsql.conf" \
    "${pkgdir}/usr/lib/systemd/system/traccar.service.d/pgsql.conf"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/traccar-pgsql.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

package_traccar-mysql() {
  arch=('all')
  depends=(
    "traccar" "dbconfig-mysql" "mariadb-server | default-mysql-server"
    "debconf" "debconf-utils"
  )
  conflicts=("traccar-pgsql")
  replaces=("traccar-pgsql")
  breaks=("traccar-pgsql")
  provides=("traccar-db")
  pkgdesc="Traccar MySQL/MariaDB storage (dbconfig-mysql)"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/traccar-mysql/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/traccar-mysql/install/mysql"

  install -Dm644 "${srcdir}/mysql.conf" \
    "${pkgdir}/usr/lib/systemd/system/traccar.service.d/mysql.conf"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/traccar-mysql.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

_have_systemd() { [ -d /run/systemd/system ]; }

_traccar_ensure_user() {
  if ! getent group traccar >/dev/null; then
    groupadd --system traccar
  fi
  if ! getent passwd traccar >/dev/null; then
    useradd --system --gid traccar --home-dir /var/lib/traccar \
      --shell /usr/sbin/nologin traccar
  fi
  mkdir -p /var/lib/traccar/data /var/lib/traccar/logs /var/lib/traccar/media /etc/traccar
  chown -R traccar:traccar /var/lib/traccar
  chmod 750 /var/lib/traccar /var/lib/traccar/data /var/lib/traccar/logs /var/lib/traccar/media
  chown root:traccar /etc/traccar
  chmod 750 /etc/traccar
  if [ -f /etc/traccar/traccar.xml ]; then
    chown root:traccar /etc/traccar/traccar.xml
    chmod 640 /etc/traccar/traccar.xml
  fi
}

_traccar_set_xml_entry() {
  local file="$1" key="$2" value="$3"
  local tmp
  tmp="$(mktemp)"
  # Escape for sed replacement: &, \, and newlines are not expected in values.
  local esc
  esc="$(printf '%s' "${value}" | sed -e 's/[&|]/\\&/g')"
  if grep -q "key='${key}'" "${file}"; then
    sed -E "s|(<entry key='${key}'>)[^<]*(</entry>)|\1${esc}\2|" "${file}" > "${tmp}"
  else
    # Insert before closing </properties>
    awk -v key="${key}" -v val="${value}" '
      /<\/properties>/ {
        printf "    <entry key='\''%s'\''>%s</entry>\n", key, val
      }
      { print }
    ' "${file}" > "${tmp}"
  fi
  cat "${tmp}" > "${file}"
  rm -f "${tmp}"
}

_traccar_restart() {
  _have_systemd || return 0
  systemctl daemon-reload
  systemctl try-restart traccar.service
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

post_install() {
  set -e
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- configure

  local pkg="${DPKG_MAINTSCRIPT_PACKAGE:-}"
  local xml="/etc/traccar/traccar.xml"

  case "${pkg}" in
    traccar)
      _traccar_ensure_user
      if _have_systemd; then
        systemctl daemon-reload
        systemctl enable --now traccar.service
      fi
      ;;

    traccar-pgsql)
      _traccar_ensure_user
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postinst.pgsql
      dbc_go traccar-pgsql "$@"

      # shellcheck disable=SC1091
      . /etc/dbconfig-common/traccar-pgsql.conf

      local db_host="${dbc_dbserver:-127.0.0.1}"
      case "$db_host" in local|localhost) db_host="127.0.0.1" ;; esac

      local use_pw=1
      if [ "${dbc_install}" != "true" ]; then
        dbc_dbname="${dbc_dbname:-traccar}"
        dbc_dbuser="${dbc_dbuser:-traccar}"
        use_pw=0
      else
        case "${dbc_authmethod_user}:${dbc_dbserver:-local}" in
          ident:local|ident:|ident:localhost|ident:127.0.0.1) use_pw=0 ;;
        esac
      fi

      local jdbc_url=""
      if [ "${use_pw}" = "1" ]; then
        ensure_pg_role_db "${dbc_dbuser}" "${dbc_dbname}" "${dbc_dbpass}"
        jdbc_url="jdbc:postgresql://${db_host}:${dbc_dbport:-5432}/${dbc_dbname}"
        _traccar_set_xml_entry "${xml}" database.password "${dbc_dbpass}"
      else
        ensure_pg_role_db "${dbc_dbuser}" "${dbc_dbname}"
        # Peer/ident via Unix socket — JDBC still needs host; use localhost.
        jdbc_url="jdbc:postgresql://127.0.0.1:${dbc_dbport:-5432}/${dbc_dbname}"
        _traccar_set_xml_entry "${xml}" database.password ""
      fi
      _traccar_set_xml_entry "${xml}" database.driver "org.postgresql.Driver"
      _traccar_set_xml_entry "${xml}" database.url "${jdbc_url}"
      _traccar_set_xml_entry "${xml}" database.user "${dbc_dbuser}"

      chown root:traccar "${xml}"
      chmod 640 "${xml}"
      db_stop
      _traccar_restart
      ;;

    traccar-mysql)
      _traccar_ensure_user
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postinst.mysql
      dbc_go traccar-mysql "$@"

      # shellcheck disable=SC1091
      . /etc/dbconfig-common/traccar-mysql.conf

      local db_host="${dbc_dbserver:-127.0.0.1}"
      case "$db_host" in local|localhost) db_host="127.0.0.1" ;; esac
      local db_port="${dbc_dbport:-3306}"
      local db_user="${dbc_dbuser:-traccar}"
      local db_name="${dbc_dbname:-traccar}"
      local db_pass="${dbc_dbpass:-}"

      local jdbc_url="jdbc:mysql://${db_host}:${db_port}/${db_name}?zeroDateTimeBehavior=round&serverTimezone=UTC&allowPublicKeyRetrieval=true&useSSL=false&allowMultiQueries=true&rewriteBatchedStatements=true&autoReconnect=true&useUnicode=yes&characterEncoding=UTF-8&sessionVariables=sql_mode=''"

      _traccar_set_xml_entry "${xml}" database.driver "com.mysql.cj.jdbc.Driver"
      _traccar_set_xml_entry "${xml}" database.url "${jdbc_url}"
      _traccar_set_xml_entry "${xml}" database.user "${db_user}"
      _traccar_set_xml_entry "${xml}" database.password "${db_pass}"

      chown root:traccar "${xml}"
      chmod 640 "${xml}"
      db_stop
      _traccar_restart
      ;;
  esac
}

pre_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  local pkg="${DPKG_MAINTSCRIPT_PACKAGE:-}"
  case "${pkg}" in
    traccar)
      if _have_systemd; then
        systemctl stop traccar.service || true
        systemctl disable traccar.service || true
      fi
      ;;
    traccar-pgsql)
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/prerm.pgsql
      dbc_go traccar-pgsql "$@"
      ;;
    traccar-mysql)
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/prerm.mysql
      dbc_go traccar-mysql "$@"
      ;;
  esac
}

post_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  local pkg="${DPKG_MAINTSCRIPT_PACKAGE:-}"
  case "${pkg}" in
    traccar)
      _have_systemd && systemctl daemon-reload || true
      ;;
    traccar-pgsql)
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postrm.pgsql
      dbc_go traccar-pgsql "$@"
      ;;
    traccar-mysql)
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postrm.mysql
      dbc_go traccar-mysql "$@"
      ;;
  esac
}
