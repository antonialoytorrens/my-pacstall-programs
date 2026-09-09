pkgname="fail2ban-ui"
pkgver="1.5.4"
pkgrel="3"
arch=('amd64' 'arm64' 'armhf')
url="https://github.com/swissmakers/fail2ban-ui"
license=('AGPL-3.0')
pkgdesc="Web UI for managing Fail2ban (local and remote)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/my-pacstall-programs>")
external_connection=true

# Pacstall calls hooks with no args; dpkg argv is available at top-level when embedded.
_DPKG_ARGV=("$@")

source=(
  "https://github.com/swissmakers/fail2ban-ui/archive/refs/tags/v${pkgver}.tar.gz"
  "fail2ban-ui.service"
  "fail2ban-ui.env"
)

makedepends+=(
  "ca-certificates" "curl" "git" "golang"
)

depends=(
  "ca-certificates" "systemd"
)

recommends=("fail2ban" "whois" "openssh-client")
backup=('etc/fail2ban-ui/fail2ban-ui.env')

# Go from Debian trixie-backports (see docker/fail2ban-ui/Dockerfile).
# CGO_ENABLED=0 — sqlite via modernc.org.

build() {
  set -e
  export CGO_ENABLED=0
  export GOCACHE="${srcdir}/.gocache"
  export GOMODCACHE="${srcdir}/.gomodcache"

  cd "${srcdir}/fail2ban-ui-${pkgver}"
  go build -trimpath -ldflags="-s -w" -o fail2ban-ui ./cmd/server/main.go
}

package() {
  install -Dm755 "${srcdir}/fail2ban-ui-${pkgver}/fail2ban-ui" \
    "${pkgdir}/usr/bin/fail2ban-ui"

  install -Dm644 "${srcdir}/fail2ban-ui.service" \
    "${pkgdir}/usr/lib/systemd/system/fail2ban-ui.service"

  install -Dm640 "${srcdir}/fail2ban-ui.env" \
    "${pkgdir}/etc/fail2ban-ui/fail2ban-ui.env"

  mkdir -p "${pkgdir}/var/lib/fail2ban-ui"
}

_fail2ban_ui_ensure_user() {
  if ! getent group fail2ban-ui >/dev/null; then
    groupadd --system fail2ban-ui
  fi
  if ! getent passwd fail2ban-ui >/dev/null; then
    useradd --system --gid fail2ban-ui --home-dir /var/lib/fail2ban-ui \
      --shell /usr/sbin/nologin fail2ban-ui
  fi
  mkdir -p /var/lib/fail2ban-ui /etc/fail2ban-ui
  chown fail2ban-ui:fail2ban-ui /var/lib/fail2ban-ui
  chmod 750 /var/lib/fail2ban-ui
  chown root:fail2ban-ui /etc/fail2ban-ui
  chmod 750 /etc/fail2ban-ui
  if [ -f /etc/fail2ban-ui/fail2ban-ui.env ]; then
    chown root:fail2ban-ui /etc/fail2ban-ui/fail2ban-ui.env
    chmod 640 /etc/fail2ban-ui/fail2ban-ui.env
  fi
}

post_install() {
  set -e
  if [ "$#" -eq 0 ] && [ "${#_DPKG_ARGV[@]}" -gt 0 ]; then
    set -- "${_DPKG_ARGV[@]}"
  elif [ "$#" -eq 0 ]; then
    set -- configure
  fi

  _fail2ban_ui_ensure_user
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl enable fail2ban-ui.service || true
    systemctl start fail2ban-ui.service || true
  fi
}

pre_remove() {
  if [ "$#" -eq 0 ] && [ "${#_DPKG_ARGV[@]}" -gt 0 ]; then
    set -- "${_DPKG_ARGV[@]}"
  elif [ "$#" -eq 0 ]; then
    set -- remove
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop fail2ban-ui.service 2>/dev/null || true
    systemctl disable fail2ban-ui.service 2>/dev/null || true
  fi
}

post_remove() {
  if [ "$#" -eq 0 ] && [ "${#_DPKG_ARGV[@]}" -gt 0 ]; then
    set -- "${_DPKG_ARGV[@]}"
  elif [ "$#" -eq 0 ]; then
    set -- remove
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
  fi
}
