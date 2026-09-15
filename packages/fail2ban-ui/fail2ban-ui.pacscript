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

# Go from Debian trixie-backports (shared docker/Dockerfile).
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
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- configure

  _fail2ban_ui_ensure_user
  systemctl daemon-reload
  systemctl enable --now fail2ban-ui.service
}

pre_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  systemctl disable --now fail2ban-ui.service
}

post_remove() {
  [ $# -eq 0 ] && set -- "${_DPKG_ARGV[@]}"
  [ $# -eq 0 ] && set -- remove

  systemctl daemon-reload
}
