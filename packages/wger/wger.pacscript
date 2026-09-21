pkgbase="wger"
pkgname=("wger" "wger-pgsql" "wger-sqlite" "wger-powersync")
pkgver="2.7"
pkgrel="3"
arch=('amd64' 'arm64' 'armhf')
url="https://wger.de/"
license=('AGPL-3.0-or-later')
pkgdesc="wger Workout Manager (bundled venv, native systemd)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/wger-deb>")
external_connection=true

_wger_domain="wger.localhost.local"
_wger_db_name="wger"
_wger_db_user="wger"
_wger_db_host="127.0.0.1"
_wger_http_port="38437"
_wger_powersync_port="38438"

_src="wger-${pkgver}"
_install_prefix="/opt/wger"
_python="python3"

# lingua-language-detector on PyPI is wheel-only (amd64/arm64); no armhf/sdist.
# Build the same reduced wheel on every arch so install paths stay identical.
_lingua_rs_commit="77e94d1a2a8e49bed873a7c502bcb51ba803ef0f"
_maturin_version="1.11.5"
_psycopg_c_version="3.3.4"

# PowerSync: Node + service. Runtime only on amd64/arm64.
_node_version="24.18.1"
_powersync_version="1.26.1"
_pnpm_version="11.0.9"

# Pacstall calls hooks with no args; dpkg argv is available at top-level when embedded.
_DPKG_ARGV=("$@")

source=(
  "wger-${pkgver}.tar.gz::https://github.com/wger-project/wger/archive/refs/tags/${pkgver}.tar.gz"
  "0001-psycopg-drop-binary-extra.patch"
  "wger.env.in"
  "wger-pgsql.config.in"
  "wger-sqlite.config.in"
  "wger.service"
  "wger-celery-worker.service"
  "wger-celery-beat.service"
  "wger.tmpfiles"
  "pgsql.conf"
  "powersync.yaml"
  "sync_rules.yaml"
  "postgresql-wger-powersync.conf"
  "wger-powersync.service"
  "wger-powersync-compact.service"
  "wger-powersync-compact.timer"
)

makedepends+=(
  "python3" "python3-venv" "python3-dev" "python3-pip"
  "build-essential" "pkg-config" "patch"
  "libpq-dev" "zlib1g-dev" "libwebp-dev"
  "libssl-dev" "libffi-dev"
  "gettext" "curl" "ca-certificates" "tzdata" "git"
  "nodejs" "npm"
  "rustc" "cargo"
)
makedepends_debian=("libjpeg62-turbo-dev")
makedepends_resolute=("libjpeg-turbo8-dev")

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

  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel,pkg_resources}
  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel}-*.dist-info
  find "${venv}" -depth -type d -name __pycache__ -exec rm -rf {} +
  find "${venv}" -name "*.pyc" -delete
  find "${venv}" -name "*.so" -exec strip --strip-unneeded {} +

  local site_pkgs
  site_pkgs="$(echo "${venv}/lib"/python*/site-packages)"
  find "${site_pkgs}" -depth -maxdepth 3 -type d \( -name tests -o -name test \) \
    -not -path "*/django/*" \
    -not -path "*/celery/*" \
    -exec rm -rf {} +

  find "${src_dest}" -depth -type d -name __pycache__ -exec rm -rf {} +

  # PowerSync: Node + build service
  local dpkg_arch node_arch
  dpkg_arch="$(dpkg --print-architecture)"
  case "${dpkg_arch}" in
    amd64) node_arch="x64" ;;
    arm64) node_arch="arm64" ;;
    *) return 0 ;;
  esac

  local ps_node="${staging}${_install_prefix}/powersync/node"
  local ps_app="${staging}${_install_prefix}/powersync/app"
  mkdir -p "${ps_node}"
  curl -fsSL \
    "https://nodejs.org/dist/v${_node_version}/node-v${_node_version}-linux-${node_arch}.tar.xz" \
    | tar -xJ -C "${ps_node}" --strip-components=1

  local ps_src="${srcdir}/powersync-service-${_powersync_version}"
  curl -fsSL \
    "https://github.com/powersync-ja/powersync-service/archive/refs/tags/v${_powersync_version}.tar.gz" \
    | tar -xz -C "${srcdir}"

  (
    export PATH="${ps_node}/bin:${PATH}"
    cd "${ps_src}"
    corepack enable
    corepack prepare "pnpm@${_pnpm_version}" --activate
    pnpm install --frozen-lockfile
    pnpm build:production
    shopt -s globstar nullglob
    rm -rf node_modules **/node_modules
    pnpm install --frozen-lockfile --prod --ignore-scripts
  )

  mkdir -p "${ps_app}"
  cp -a "${ps_src}/." "${ps_app}/"
  rm -rf "${ps_app}/.git" "${ps_app}/docs" "${ps_app}/test-client"
}

_render_in() {
  sed -e "s|@WGER_DOMAIN@|${_wger_domain}|g" \
      -e "s|@pkgver@|${pkgver}|g" \
      -e "s|@WGER_DB_NAME@|${_wger_db_name}|g" \
      -e "s|@WGER_DB_USER@|${_wger_db_user}|g" \
      -e "s|@WGER_DB_HOST@|${_wger_db_host}|g" \
      -e "s|@WGER_HTTP_PORT@|${_wger_http_port}|g" \
      -e "s|@WGER_POWERSYNC_PORT@|${_wger_powersync_port}|g" \
      "${1}" > "${2}"
}

package_wger() {
  depends=(
    "python3" "gunicorn" "systemd"
    "libpq5" "libwebp7" "gettext-base" "tzdata"
    "wger-pgsql | wger-sqlite | dbconfig-no-thanks"
  )
  depends_debian=("libjpeg62-turbo")
  depends_resolute=("libjpeg-turbo8")
  recommends=("valkey-server")
  backup=('etc/wger/wger.env')
  pkgdesc="wger Workout Manager (bundled venv, native systemd)"

  local staging="${srcdir}/staging"
  mkdir -p "${pkgdir}${_install_prefix}"
  cp -a "${staging}${_install_prefix}/src" "${pkgdir}${_install_prefix}/"
  cp -a "${staging}${_install_prefix}/venv" "${pkgdir}${_install_prefix}/"

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
}

package_wger-pgsql() {
  arch=('all')
  depends=("wger" "dbconfig-pgsql" "postgresql" "debconf" "debconf-utils")
  conflicts=("wger-sqlite")
  replaces=("wger-sqlite")
  breaks=("wger-sqlite")
  provides=("wger-db")
  pkgdesc="wger PostgreSQL storage (dbconfig-pgsql)"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/wger-pgsql/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/wger-pgsql/install/pgsql"

  install -Dm644 "${srcdir}/pgsql.conf" \
    "${pkgdir}/usr/lib/systemd/system/wger.service.d/pgsql.conf"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/wger-pgsql.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

package_wger-sqlite() {
  arch=('all')
  depends=("wger" "dbconfig-sqlite3" "debconf" "debconf-utils")
  conflicts=("wger-pgsql")
  replaces=("wger-pgsql")
  breaks=("wger-pgsql")
  provides=("wger-db")
  pkgdesc="wger SQLite storage (dbconfig-sqlite3)"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/wger-sqlite/install"
  printf 'SELECT 1;\n' > "${pkgdir}/usr/share/dbconfig-common/data/wger-sqlite/install/sqlite3"

  mkdir -p "${pkgdir}/DEBIAN"
  _render_in "${srcdir}/wger-sqlite.config.in" "${pkgdir}/DEBIAN/config"
  chmod 755 "${pkgdir}/DEBIAN/config"
}

package_wger-powersync() {
  depends=("wger" "wger-pgsql")
  pkgdesc="wger PowerSync service (native Node, mobile offline sync)"
  backup=('etc/wger/powersync/powersync.yaml' 'etc/wger/powersync/sync_rules.yaml')

  # Node binary only for amd64/arm64; armhf gets stub so CI pkgname loop still works.
  case "$(dpkg --print-architecture)" in
    amd64|arm64) ;;
    *)
      mkdir -p "${pkgdir}/usr/share/doc/wger-powersync"
      printf 'PowerSync not supported on this architecture.\n' \
        > "${pkgdir}/usr/share/doc/wger-powersync/README"
      return 0
      ;;
  esac

  local staging="${srcdir}/staging"
  mkdir -p "${pkgdir}${_install_prefix}/powersync"
  cp -a "${staging}${_install_prefix}/powersync/." "${pkgdir}${_install_prefix}/powersync/"

  mkdir -p "${pkgdir}/etc/wger/powersync"
  install -Dm644 "${srcdir}/powersync.yaml" \
    "${pkgdir}/etc/wger/powersync/powersync.yaml"
  install -Dm644 "${srcdir}/sync_rules.yaml" \
    "${pkgdir}/etc/wger/powersync/sync_rules.yaml"

  install -Dm644 "${srcdir}/postgresql-wger-powersync.conf" \
    "${pkgdir}/usr/share/wger/postgresql-wger-powersync.conf"

  install -Dm644 "${srcdir}/wger-powersync.service" \
    "${pkgdir}/usr/lib/systemd/system/wger-powersync.service"
  install -Dm644 "${srcdir}/wger-powersync-compact.service" \
    "${pkgdir}/usr/lib/systemd/system/wger-powersync-compact.service"
  install -Dm644 "${srcdir}/wger-powersync-compact.timer" \
    "${pkgdir}/usr/lib/systemd/system/wger-powersync-compact.timer"
}

_have_systemd() { [ -d /run/systemd/system ]; }

_wger_ensure_user() {
  if ! id -u wger &>/dev/null; then
    adduser --system --group --home /var/lib/wger \
      --no-create-home --shell /bin/bash wger
  fi
  mkdir -p /var/lib/wger/media /var/lib/wger/static /var/log/wger
  chown -R wger:wger /var/lib/wger /var/log/wger
}

_wger_run_as() {
  local env_file="/etc/wger/wger.env" src="/opt/wger/src"
  runuser -u wger -- bash -c '
    set -a; source "$1"; set +a
    cd "$2" || exit 1
    shift 2
    exec "$@"
  ' bash "$env_file" "$src" "$@"
}

_wger_write_db_env() {
  local env_file="/etc/wger/wger.env"
  grep -vE '^(DJANGO_DB_ENGINE|DJANGO_DB_DATABASE|DJANGO_DB_USER|DJANGO_DB_PASSWORD|DJANGO_DB_HOST|DJANGO_DB_PORT)=' \
    "$env_file" > "${env_file}.tmp"
  {
    cat "${env_file}.tmp"
    cat
  } > "$env_file"
  rm -f "${env_file}.tmp"
  chmod 640 "$env_file"
  chown root:wger "$env_file"
}

_wger_bootstrap() {
  local venv="/opt/wger/venv"
  _wger_run_as "${venv}/bin/wger" bootstrap --no-process-static
  _wger_run_as "${venv}/bin/django-admin" migrate --noinput
  _wger_run_as "${venv}/bin/django-admin" collectstatic --noinput
  _wger_run_as "${venv}/bin/django-admin" set-site-url
  fancy_message warn "Default admin (first install only): admin / adminadmin — CHANGE THIS PASSWORD immediately."
  chmod 755 /var/lib/wger
  chmod -R g+rX /var/lib/wger/static
}

_wger_restart() {
  _have_systemd || return 0
  systemctl daemon-reload
  # Enable only — never start in postinst (installers/CI may lack a full runtime).
  systemctl enable wger.service
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
  local venv="/opt/wger/venv"
  local env_file="/etc/wger/wger.env"

  case "${pkg}" in
    wger)
      _wger_ensure_user

      if grep -q '__SECRETKEY_PLACEHOLDER__' "$env_file"; then
        local secret
        secret=$("$venv/bin/python" -c "import secrets; print(secrets.token_urlsafe(50))")
        sed -i "s|__SECRETKEY_PLACEHOLDER__|${secret}|" "$env_file"
      fi

      if grep -q '__JWTPRIVATE_PLACEHOLDER__' "$env_file"; then
        local jwt_output jwt_private jwt_public
        # Generate JWKs without django-admin: settings.main decodes JWT_* at
        # import, so placeholders cannot be sourced into a management command.
        jwt_output=$("$venv/bin/python" -c '
from base64 import urlsafe_b64encode
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)

def b64jwk(key):
    return urlsafe_b64encode(RSAAlgorithm.to_jwk(key).encode()).decode()

print("JWT_PRIVATE_KEY=" + b64jwk(priv))
print("JWT_PUBLIC_KEY=" + b64jwk(priv.public_key()))
')
        jwt_private=$(printf '%s\n' "${jwt_output}" | grep '^JWT_PRIVATE_KEY=' | cut -d= -f2-)
        jwt_public=$(printf '%s\n' "${jwt_output}" | grep '^JWT_PUBLIC_KEY=' | cut -d= -f2-)
        sed -i "s|__JWTPRIVATE_PLACEHOLDER__|${jwt_private}|" "$env_file"
        sed -i "s|__JWTPUBLIC_PLACEHOLDER__|${jwt_public}|" "$env_file"
      fi

      chmod 640 "$env_file"
      chown root:wger "$env_file"

      if _have_systemd; then
        systemd-tmpfiles --create /usr/lib/tmpfiles.d/wger.conf
        systemctl daemon-reload
        # DB helpers start the service after bootstrap.
        systemctl enable wger
      fi
      ;;

    wger-pgsql)
      _wger_ensure_user
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postinst.pgsql
      dbc_go wger-pgsql "$@"

      # shellcheck disable=SC1091
      . /etc/dbconfig-common/wger-pgsql.conf

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

      if [ "${use_pw}" = "1" ]; then
        _wger_write_db_env << EOF
DJANGO_DB_ENGINE=django.db.backends.postgresql
DJANGO_DB_DATABASE=${dbc_dbname}
DJANGO_DB_USER=${dbc_dbuser}
DJANGO_DB_PASSWORD=${dbc_dbpass}
DJANGO_DB_HOST=${db_host}
DJANGO_DB_PORT=${dbc_dbport:-5432}
EOF
      else
        _wger_write_db_env << EOF
DJANGO_DB_ENGINE=django.db.backends.postgresql
DJANGO_DB_DATABASE=${dbc_dbname}
DJANGO_DB_USER=${dbc_dbuser}
DJANGO_DB_HOST=${db_host}
DJANGO_DB_PORT=${dbc_dbport:-5432}
EOF
      fi

      _wger_bootstrap
      db_stop
      _wger_restart
      ;;

    wger-sqlite)
      _wger_ensure_user
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postinst.sqlite3
      dbc_go wger-sqlite "$@"

      local sqlite_path="/var/lib/wger/db.sqlite3"
      _wger_write_db_env << EOF
DJANGO_DB_ENGINE=django.db.backends.sqlite3
DJANGO_DB_DATABASE=${sqlite_path}
EOF
      chown wger:wger /var/lib/wger

      _wger_bootstrap
      db_stop
      _wger_restart
      ;;

    wger-powersync)
      if [ ! -d /opt/wger/powersync/app ]; then
        fancy_message warn "PowerSync not supported on this architecture."
      else
      # shellcheck disable=SC1091
      . /etc/dbconfig-common/wger-pgsql.conf

      local db_host="${dbc_dbserver:-127.0.0.1}"
      case "$db_host" in local|localhost) db_host="127.0.0.1" ;; esac
      local db_name="${dbc_dbname}"
      local db_port="${dbc_dbport:-5432}"
      local sslmode=disable
      case "$db_host" in
        127.0.0.1|localhost|::1) ;;
        *) sslmode=verify-full ;;
      esac

      # logical wal for sync
      local confd
      for confd in /etc/postgresql/*/main/conf.d; do
        [ -d "$confd" ] || continue
        install -m644 /usr/share/wger/postgresql-wger-powersync.conf \
          "$confd/wger-powersync.conf"
      done
      fancy_message warn "Restart PostgreSQL so wal_level=logical takes effect."

      local repl_pass storage_pass
      if ! grep -q '^PS_DATABASE_URI=' "$env_file"; then
        repl_pass=$(/opt/wger/venv/bin/python -c "import secrets; print(secrets.token_urlsafe(24))")
        printf 'PS_DATABASE_URI=postgres://powersync_replication:%s@%s:%s/%s\n' \
          "$repl_pass" "$db_host" "$db_port" "$db_name" >> "$env_file"
      else
        repl_pass=$(sed -n 's|^PS_DATABASE_URI=postgres://powersync_replication:\([^@]*\)@.*|\1|p' "$env_file")
      fi

      if ! grep -q '^PS_STORAGE_PG_URI=' "$env_file"; then
        storage_pass=$(/opt/wger/venv/bin/python -c "import secrets; print(secrets.token_urlsafe(24))")
        printf 'PS_STORAGE_PG_URI=postgres://powersync_storage:%s@%s:%s/%s\n' \
          "$storage_pass" "$db_host" "$db_port" "$db_name" >> "$env_file"
      else
        storage_pass=$(sed -n 's|^PS_STORAGE_PG_URI=postgres://powersync_storage:\([^@]*\)@.*|\1|p' "$env_file")
      fi

      if ! grep -q '^PS_PORT=' "$env_file"; then
        printf 'PS_PORT=%s\n' "${_wger_powersync_port}" >> "$env_file"
      fi
      if ! grep -q '^POWERSYNC_URL_PATH=' "$env_file"; then
        printf 'POWERSYNC_URL_PATH=ps\n' >> "$env_file"
      fi
      if ! grep -q '^PS_JWKS_URL=' "$env_file"; then
        local http_port
        http_port=$(grep '^WGER_HTTP_PORT=' "$env_file" | cut -d= -f2-)
        printf 'PS_JWKS_URL=http://127.0.0.1:%s/api/v2/powersync-keys\n' \
          "${http_port:-${_wger_http_port}}" >> "$env_file"
      fi
      if ! grep -q '^PS_PG_SSLMODE=' "$env_file"; then
        printf 'PS_PG_SSLMODE=%s\n' "$sslmode" >> "$env_file"
      fi

      chmod 640 "$env_file"
      chown root:wger "$env_file"

      # dedicated replication + storage roles (not the Django app role)
      ensure_pg_role_db powersync_replication "$db_name" "$repl_pass"
      ensure_pg_role_db powersync_storage "$db_name" "$storage_pass"
      runuser -u postgres -- psql -d "$db_name" -v ON_ERROR_STOP=1 <<SQL
ALTER ROLE powersync_replication WITH REPLICATION;
GRANT CONNECT ON DATABASE ${db_name} TO powersync_replication;
GRANT USAGE ON SCHEMA public TO powersync_replication;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO powersync_replication;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO powersync_replication;
CREATE SCHEMA IF NOT EXISTS powersync AUTHORIZATION powersync_storage;
GRANT CONNECT ON DATABASE ${db_name} TO powersync_storage;
SQL

      # allow outbound to remote PG (service unit already allows loopback)
      case "$db_host" in
        127.0.0.1|localhost|::1) ;;
        *)
          mkdir -p /etc/systemd/system/wger-powersync.service.d
          printf '%s\n' '[Service]' "IPAddressAllow=${db_host}" \
            > /etc/systemd/system/wger-powersync.service.d/remote-db.conf
          ;;
      esac

      if _have_systemd; then
        systemctl daemon-reload
        systemctl enable wger-powersync.service
        systemctl enable wger-powersync-compact.timer
      fi

      fancy_message warn "Proxy /ps/ to 127.0.0.1:${_wger_powersync_port} (no buffering, long timeouts). Then: systemctl start wger-powersync"
      fi
      ;;
  esac
}

pre_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  local pkg="${DPKG_MAINTSCRIPT_PACKAGE:-}"
  case "${pkg}" in
    wger)
      if _have_systemd; then
        systemctl stop wger wger-celery-worker wger-celery-beat
        systemctl disable wger wger-celery-worker wger-celery-beat
      fi
      ;;
    wger-powersync)
      if _have_systemd; then
        systemctl stop wger-powersync wger-powersync-compact.timer
        systemctl disable wger-powersync wger-powersync-compact.timer
      fi
      ;;
    wger-pgsql)
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/prerm.pgsql
      dbc_go wger-pgsql "$@"
      ;;
    wger-sqlite)
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/prerm.sqlite3
      dbc_go wger-sqlite "$@"
      ;;
  esac
}

post_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  local pkg="${DPKG_MAINTSCRIPT_PACKAGE:-}"
  case "${pkg}" in
    wger)
      _have_systemd && systemctl daemon-reload
      ;;
    wger-powersync)
      _have_systemd && systemctl daemon-reload
      ;;
    wger-pgsql)
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postrm.pgsql
      dbc_go wger-pgsql "$@"
      ;;
    wger-sqlite)
      . /usr/share/debconf/confmodule
      . /usr/share/dbconfig-common/dpkg/postrm.sqlite3
      dbc_go wger-sqlite "$@"
      ;;
  esac
}
