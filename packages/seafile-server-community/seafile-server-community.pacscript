pkgname="seafile-server-community"
pkgver="13.0.25"
pkgrel="1"
arch=('amd64' 'arm64')
url="https://github.com/haiwen/seafile-server"
license=('AGPL-3.0-or-later')
pkgdesc="Seafile Community Edition server (bundled stack, native systemd, dbconfig-mysql)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/my-pacstall-programs>")
external_connection=true

_seafile_db_name="seafile"
_seafile_db_user="seafile"
_install_root="/opt/seafile"
_install_path="${_install_root}/seafile-server-${pkgver}"

# Pacstall calls hooks with no args; dpkg argv is available at top-level when embedded.
_DPKG_ARGV=("$@")

source=(
  "seafile-server-${pkgver}-server.tar.gz::https://github.com/haiwen/seafile-server/archive/refs/tags/v${pkgver}-server.tar.gz"
  "seahub-${pkgver}-server.tar.gz::https://github.com/haiwen/seahub/archive/refs/tags/v${pkgver}-server.tar.gz"
  "seafevents-${pkgver}-server.tar.gz::https://github.com/haiwen/seafevents/archive/refs/tags/v${pkgver}-server.tar.gz"
  "0001-fix-objcache-new-signature.patch"
  "0002-fix-evhtp-hook-callback-pointer-types.patch"
  "seahub-requirements.txt"
  "seafevents-requirements.txt"
  "ccnet.conf.dbconfig.tmpl"
  "seafile.conf.dbconfig.tmpl"
  "seahub_settings.py.dbconfig.tmpl"
  "seafevents.conf.tmpl"
  "seafile-server.service"
  "seafile-notification.service"
  "seahub.service"
  "seafevents.service"
  "seafile-server-community.config.in"
  "nginx.example"
  "apache2.example"
)

makedepends_trixie=(
  "python3.13" "python3.13-venv" "python3.13-dev"
)

makedepends_resolute=(
  "python3" "python3-venv" "python3-dev"
)

makedepends+=(
  "build-essential" "pkg-config" "patch"
  "autoconf" "automake" "libtool" "intltool" "valac"
  "golang-go" "git"
  "libsearpc-dev" "libevhtp-dev" "libjwt-dev" "libargon2-dev" "libhiredis-dev"
  "libarchive-dev" "libmariadb-dev" "libmariadb-dev-compat"
  "libevent-dev" "libfuse-dev" "libjansson-dev" "libglib2.0-dev"
  "libcurl4-openssl-dev" "libssl-dev" "uuid-dev" "zlib1g-dev"
  "libldap2-dev" "libsasl2-dev" "libjpeg-dev" "libwebp-dev"
  "libcairo2-dev"
  "nodejs" "npm" "gettext"
  "curl" "ca-certificates" "tzdata"
)

depends_trixie=(
  "python3.13" "libjpeg62-turbo"
)

depends_resolute=(
  "python3" "libjpeg-turbo8"
)

depends+=(
  "libsearpc1t64" "python3-searpc" "libevhtp0t64"
  "libjwt2" "libargon2-1" "libhiredis1.1.0" "libarchive13t64"
  "libmariadb3" "libevent-2.1-7t64" "libfuse2t64" "libjansson4"
  "libglib2.0-0t64" "libcurl4t64" "libssl3t64" "libuuid1" "zlib1g"
  "libcairo2" "libwebp7" "libldap2" "libsasl2-2"
  "mariadb-server | default-mysql-server"
  "dbconfig-mysql | dbconfig-no-thanks"
  "dbconfig-common" "debconf" "debconf-utils" "ucf"
  "adduser" "systemd" "ca-certificates"
)

recommends=("nginx" "valkey-server | redis-server")

_server_src="seafile-server-${pkgver}-server"
_seahub_src="seahub-${pkgver}-server"
_events_src="seafevents-${pkgver}-server"

prepare() {
  set -e
  cd "${srcdir}/${_server_src}"
  patch -p1 --forward -i "${srcdir}/0001-fix-objcache-new-signature.patch"
  patch -p1 --forward -i "${srcdir}/0002-fix-evhtp-hook-callback-pointer-types.patch"
}

_venv_relocate() {
  local venv="$1" from="$2" to="$3"
  sed -i "s|${from}|${to}|g" "${venv}/pyvenv.cfg"
  find "${venv}/bin" -maxdepth 1 -type f -exec sed -i "s|${from}|${to}|g" {} +
}

_venv_cleanup() {
  local venv="$1"
  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel,pkg_resources}
  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel}-*.dist-info
  find "${venv}" -depth -type d -name __pycache__ -exec rm -rf {} +
  find "${venv}" -name "*.pyc" -delete
  find "${venv}" -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true
}

_copy_seaserv_into_venv() {
  local venv="$1" py_src="$2"
  local site_pkgs
  site_pkgs="$(echo "${venv}/lib"/python*/site-packages)"
  mkdir -p "${site_pkgs}"
  cp -a "${py_src}/." "${site_pkgs}/"
}

build() {
  set -e
  local staging="${srcdir}/staging"
  local server_tmp="${srcdir}/server-destdir"
  local py_tmp="${srcdir}/seaserv-python"
  mkdir -p "${staging}${_install_path}/seafile/bin" \
           "${staging}${_install_path}/seafile/lib" \
           "${server_tmp}" "${py_tmp}"

  (
    cd "${srcdir}/${_server_src}"
    ./autogen.sh
    ./configure --prefix=/usr \
      --with-mysql=/usr/bin/mysql_config \
      --enable-fuse \
      --enable-python
    make -j"$(nproc)"
    make DESTDIR="${server_tmp}" install \
      pyexecdir=/usr/lib/python3/dist-packages \
      pythondir=/usr/lib/python3/dist-packages

    for pkg in fileserver notification-server; do
      (
        cd "${pkg}"
        CGO_ENABLED=1 GOFLAGS="-mod=mod -trimpath" \
          go build -o "${pkg}" -ldflags="-s -w" .
      )
    done
  )

  local bin
  for bin in seaf-server seafile-controller seaf-fuse seafserv-gc seaf-fsck; do
    install -Dm755 "${server_tmp}/usr/bin/${bin}" \
      "${staging}${_install_path}/seafile/bin/${bin}"
  done
  install -Dm755 "${srcdir}/${_server_src}/fileserver/fileserver" \
    "${staging}${_install_path}/seafile/bin/fileserver"
  install -Dm755 "${srcdir}/${_server_src}/notification-server/notification-server" \
    "${staging}${_install_path}/seafile/bin/notification-server"

  find "${staging}${_install_path}/seafile/bin" -type f -exec strip --strip-unneeded {} + 2>/dev/null || true

  if [ -d "${server_tmp}/usr/lib/python3/dist-packages" ]; then
    cp -a "${server_tmp}/usr/lib/python3/dist-packages/." "${py_tmp}/"
  fi

  # --- seahub ---
  local seahub_src="${srcdir}/${_seahub_src}"
  local seahub_dest="${staging}${_install_path}/seahub"
  local seahub_venv_build="${srcdir}/seahub-venv-build"
  mkdir -p "${seahub_dest}"
  python3 -m venv --system-site-packages "${seahub_venv_build}"
  "${seahub_venv_build}/bin/pip" install -q --no-cache-dir --upgrade pip setuptools wheel
  "${seahub_venv_build}/bin/pip" install -q --no-cache-dir --no-binary mysqlclient,python-ldap \
    -r "${srcdir}/seahub-requirements.txt"

  (
    cd "${seahub_src}/frontend"
    npm install --silent
    npm run --silent build
  )
  (
    cd "${seahub_src}"
    "${seahub_venv_build}/bin/django-admin" compilemessages --settings=seahub.settings || true
    PYTHONPATH="${seahub_src}" "${seahub_venv_build}/bin/python3" manage.py compilejsi18n \
      --settings=seahub.settings || true
  )

  rm -rf "${seahub_src}/frontend/node_modules"
  cp -a "${seahub_src}/." "${seahub_dest}/"
  cp -a "${seahub_venv_build}" "${seahub_dest}/venv"
  _venv_relocate "${seahub_dest}/venv" "${seahub_venv_build}" "${_install_path}/seahub/venv"
  _copy_seaserv_into_venv "${seahub_dest}/venv" "${py_tmp}"
  _venv_cleanup "${seahub_dest}/venv"
  find "${seahub_dest}" -depth -type d -name __pycache__ -exec rm -rf {} +
  find "${seahub_dest}" -name "*.pyc" -delete

  # --- seafevents ---
  local events_src="${srcdir}/${_events_src}"
  local events_dest="${staging}${_install_path}/seafevents"
  local events_venv_build="${srcdir}/seafevents-venv-build"
  mkdir -p "${events_dest}"
  python3 -m venv --system-site-packages "${events_venv_build}"
  "${events_venv_build}/bin/pip" install -q --no-cache-dir --upgrade pip setuptools wheel
  "${events_venv_build}/bin/pip" install -q --no-cache-dir \
    -r "${srcdir}/seafevents-requirements.txt"

  find "${events_src}" -maxdepth 1 -mindepth 1 \
    -exec cp -a {} "${events_dest}/" \;
  cp -a "${events_venv_build}" "${events_dest}/venv"
  _venv_relocate "${events_dest}/venv" "${events_venv_build}" "${_install_path}/seafevents/venv"
  _copy_seaserv_into_venv "${events_dest}/venv" "${py_tmp}"
  _venv_cleanup "${events_dest}/venv"
  find "${events_dest}" -depth -type d -name __pycache__ -exec rm -rf {} +
  find "${events_dest}" -name "*.pyc" -delete
}

_render_in() {
  sed -e "s|@SEAFILE_DB_NAME@|${_seafile_db_name}|g" \
      -e "s|@SEAFILE_DB_USER@|${_seafile_db_user}|g" \
      "${1}" > "${2}"
}

package() {
  local staging="${srcdir}/staging"
  mkdir -p "${pkgdir}${_install_root}"
  cp -a "${staging}${_install_root}/." "${pkgdir}${_install_root}/"
  ln -sfn "seafile-server-${pkgver}" "${pkgdir}${_install_root}/seafile-server-latest"

  mkdir -p "${pkgdir}${_install_root}/conf" \
           "${pkgdir}${_install_root}/seafile-data" \
           "${pkgdir}${_install_root}/seahub-data/media" \
           "${pkgdir}${_install_root}/logs" \
           "${pkgdir}${_install_root}/pids"

  local share="${pkgdir}/usr/share/seafile-server-community"
  install -Dm644 "${srcdir}/ccnet.conf.dbconfig.tmpl" "${share}/ccnet.conf.dbconfig.tmpl"
  install -Dm644 "${srcdir}/seafile.conf.dbconfig.tmpl" "${share}/seafile.conf.dbconfig.tmpl"
  install -Dm644 "${srcdir}/seahub_settings.py.dbconfig.tmpl" "${share}/seahub_settings.py.dbconfig.tmpl"
  install -Dm644 "${srcdir}/seafevents.conf.tmpl" "${share}/seafevents.conf.tmpl"
  install -Dm644 "${srcdir}/nginx.example" \
    "${pkgdir}/usr/share/doc/seafile-server-community/nginx.example"
  install -Dm644 "${srcdir}/apache2.example" \
    "${pkgdir}/usr/share/doc/seafile-server-community/apache2.example"

  install -Dm644 "${srcdir}/seafile-server.service" \
    "${pkgdir}/usr/lib/systemd/system/seafile-server.service"
  install -Dm644 "${srcdir}/seafile-notification.service" \
    "${pkgdir}/usr/lib/systemd/system/seafile-notification.service"
  install -Dm644 "${srcdir}/seahub.service" \
    "${pkgdir}/usr/lib/systemd/system/seahub.service"
  install -Dm644 "${srcdir}/seafevents.service" \
    "${pkgdir}/usr/lib/systemd/system/seafevents.service"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/seafile-server-community/install"
  printf 'SELECT 1;\n' > \
    "${pkgdir}/usr/share/dbconfig-common/data/seafile-server-community/install/mysql"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/seafile-server-community.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

_have_systemd() { [ -d /run/systemd/system ]; }

_seafile_ensure_user() {
  if ! id -u seafile &>/dev/null; then
    adduser --system --group --home /opt/seafile \
      --no-create-home --shell /usr/sbin/nologin seafile
  fi
  mkdir -p /opt/seafile/conf \
           /opt/seafile/seafile-data \
           /opt/seafile/seahub-data/media \
           /opt/seafile/logs \
           /opt/seafile/pids
  chown -R seafile:seafile \
    /opt/seafile/conf \
    /opt/seafile/seafile-data \
    /opt/seafile/seahub-data \
    /opt/seafile/logs \
    /opt/seafile/pids
  chmod 0750 /opt/seafile/conf /opt/seafile/seafile-data /opt/seafile/logs /opt/seafile/pids
}

_render_dbc_template() {
  local infile="$1" outfile="$2"
  DBC_DBSERVER="${dbc_dbserver:-localhost}" \
  DBC_DBPORT="${dbc_dbport:-3306}" \
  DBC_DBUSER="${dbc_dbuser:-}" \
  DBC_DBPASS="${dbc_dbpass:-}" \
  DBC_DBNAME="${dbc_dbname:-}" \
  python3 - "$infile" "$outfile" <<'PY'
import os
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
for key, env in (
    ("_DBC_DBSERVER_", "DBC_DBSERVER"),
    ("_DBC_DBPORT_", "DBC_DBPORT"),
    ("_DBC_DBUSER_", "DBC_DBUSER"),
    ("_DBC_DBPASS_", "DBC_DBPASS"),
    ("_DBC_DBNAME_", "DBC_DBNAME"),
):
    text = text.replace(key, os.environ.get(env, ""))
open(dst, "w", encoding="utf-8").write(text)
PY
}

_ucf_install() {
  local src="$1" dest="$2"
  local tmp
  tmp="$(mktemp)"
  cp -a "$src" "$tmp"
  chown seafile:seafile "$tmp"
  chmod 0640 "$tmp"
  ucf --debconf-ok "$tmp" "$dest"
  ucfr seafile-server-community "$dest"
  rm -f "$tmp"
  chown seafile:seafile "$dest"
  chmod 0640 "$dest"
}

post_install() {
  set -e
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- configure

  local pkg="seafile-server-community"
  local share="/usr/share/seafile-server-community"
  local latest="/opt/seafile/seafile-server-latest"

  . /usr/share/debconf/confmodule
  _seafile_ensure_user

  . /usr/share/dbconfig-common/dpkg/postinst.mysql
  dbc_go "$pkg" "$@"

  # shellcheck disable=SC1091
  if [ -f "/etc/dbconfig-common/${pkg}.conf" ]; then
    . "/etc/dbconfig-common/${pkg}.conf"
  fi

  local db_host="${dbc_dbserver:-localhost}"
  case "$db_host" in local) db_host="localhost" ;; esac
  dbc_dbserver="$db_host"
  dbc_dbport="${dbc_dbport:-3306}"

  if [ -n "${dbc_dbname:-}" ]; then
    local rendered
    rendered="$(mktemp)"
    _render_dbc_template "${share}/ccnet.conf.dbconfig.tmpl" "$rendered"
    _ucf_install "$rendered" /opt/seafile/conf/ccnet.conf
    _render_dbc_template "${share}/seafile.conf.dbconfig.tmpl" "$rendered"
    _ucf_install "$rendered" /opt/seafile/conf/seafile.conf
    _render_dbc_template "${share}/seahub_settings.py.dbconfig.tmpl" "$rendered"
    _ucf_install "$rendered" /opt/seafile/conf/seahub_settings.py
    rm -f "$rendered"

    if [ ! -s /opt/seafile/conf/seafevents.conf ]; then
      _render_dbc_template "${share}/seafevents.conf.tmpl" /opt/seafile/conf/seafevents.conf
      chown seafile:seafile /opt/seafile/conf/seafevents.conf
      chmod 0640 /opt/seafile/conf/seafevents.conf
    fi
  fi

  if [ -f /opt/seafile/conf/ccnet.conf ] && \
     grep -q '^ID = _CCNET_ID_$' /opt/seafile/conf/ccnet.conf 2>/dev/null; then
    local ccnet_id
    ccnet_id="$(head -c 20 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    sed -i "s/^ID = _CCNET_ID_$/ID = ${ccnet_id}/" /opt/seafile/conf/ccnet.conf
  fi

  if [ ! -s /opt/seafile/conf/.env ]; then
    local secret_key jwt_secret
    secret_key="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"
    jwt_secret="$(python3 -c 'import secrets; print(secrets.token_urlsafe(40))')"
    {
      echo "SECRET_KEY=${secret_key}"
      echo "SEAFILE_JWT_SECRET=${jwt_secret}"
    } > /opt/seafile/conf/.env.new
    chown root:seafile /opt/seafile/conf/.env.new
    chmod 0640 /opt/seafile/conf/.env.new
    mv /opt/seafile/conf/.env.new /opt/seafile/conf/.env
  fi

  if [ "${dbc_install:-}" = "true" ] || [ -n "${dbc_dbname:-}" ]; then
    export SEAFILE_CENTRAL_CONF_DIR=/opt/seafile/conf
    export SEAFILE_CONF_DIR=/opt/seafile/seafile-data
    export CCNET_CONF_DIR=/opt/seafile/conf
    export PYTHONPATH="${latest}/seahub"
    export DJANGO_SETTINGS_MODULE=seahub.settings
    if [ -s /opt/seafile/conf/.env ]; then
      set -a
      # shellcheck disable=SC1091
      . /opt/seafile/conf/.env
      set +a
    fi
    runuser -u seafile -- env \
      SEAFILE_CENTRAL_CONF_DIR="$SEAFILE_CENTRAL_CONF_DIR" \
      SEAFILE_CONF_DIR="$SEAFILE_CONF_DIR" \
      CCNET_CONF_DIR="$CCNET_CONF_DIR" \
      PYTHONPATH="$PYTHONPATH" \
      DJANGO_SETTINGS_MODULE="$DJANGO_SETTINGS_MODULE" \
      SECRET_KEY="${SECRET_KEY:-}" \
      "${latest}/seahub/venv/bin/python3" \
      "${latest}/seahub/manage.py" migrate --no-input
    runuser -u seafile -- env \
      SEAFILE_CENTRAL_CONF_DIR="$SEAFILE_CENTRAL_CONF_DIR" \
      SEAFILE_CONF_DIR="$SEAFILE_CONF_DIR" \
      CCNET_CONF_DIR="$CCNET_CONF_DIR" \
      PYTHONPATH="$PYTHONPATH" \
      DJANGO_SETTINGS_MODULE="$DJANGO_SETTINGS_MODULE" \
      SECRET_KEY="${SECRET_KEY:-}" \
      "${latest}/seahub/venv/bin/python3" \
      "${latest}/seahub/manage.py" collectstatic --no-input
  fi

  if _have_systemd; then
    systemctl daemon-reload
    systemctl enable seafile-server seafile-notification seahub seafevents
  fi

  db_stop
}

pre_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  if _have_systemd; then
    systemctl stop seafile-server seafile-notification seahub seafevents 2>/dev/null || true
    systemctl disable seafile-server seafile-notification seahub seafevents 2>/dev/null || true
  fi

  . /usr/share/debconf/confmodule
  . /usr/share/dbconfig-common/dpkg/prerm.mysql
  dbc_go seafile-server-community "$@"
}

post_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  . /usr/share/debconf/confmodule
  . /usr/share/dbconfig-common/dpkg/postrm.mysql
  dbc_go seafile-server-community "$@"

  if [ "$1" = "purge" ]; then
    ucf --purge /opt/seafile/conf/ccnet.conf 2>/dev/null || true
    ucf --purge /opt/seafile/conf/seafile.conf 2>/dev/null || true
    ucf --purge /opt/seafile/conf/seahub_settings.py 2>/dev/null || true
    ucfr --purge seafile-server-community /opt/seafile/conf/ccnet.conf 2>/dev/null || true
    ucfr --purge seafile-server-community /opt/seafile/conf/seafile.conf 2>/dev/null || true
    ucfr --purge seafile-server-community /opt/seafile/conf/seahub_settings.py 2>/dev/null || true
    rm -rf /opt/seafile/conf /opt/seafile/logs /opt/seafile/pids /opt/seafile/seahub-data
  fi

  _have_systemd && systemctl daemon-reload || true
}
