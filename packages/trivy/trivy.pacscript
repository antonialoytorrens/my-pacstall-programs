pkgname="trivy"
pkgver="0.74.0"
pkgrel="1"
arch=('amd64' 'arm64' 'armhf')
url="https://github.com/aquasecurity/trivy"
license=('Apache-2.0')
pkgdesc="Simple and comprehensive vulnerability scanner for containers"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/my-pacstall-programs>")
external_connection=true

source=(
  "https://github.com/aquasecurity/trivy/archive/refs/tags/v${pkgver}.tar.gz"
)

makedepends+=(
  "ca-certificates" "curl" "golang"
)

depends=(
  "ca-certificates"
)

build() {
  # see https://github.com/aquasecurity/trivy/discussions/9557
  export CGO_ENABLED=0
  export GOEXPERIMENT=jsonv2
  export GOCACHE="${srcdir}/.gocache"
  export GOMODCACHE="${srcdir}/.gomodcache"

  cd "${srcdir}/trivy-${pkgver}"
  go build -trimpath \
    -ldflags="-s -w -X github.com/aquasecurity/trivy/pkg/version/app.ver=${pkgver}" \
    -o trivy ./cmd/trivy
}

package() {
  install -Dm755 "${srcdir}/trivy-${pkgver}/trivy" \
    "${pkgdir}/usr/bin/trivy"
}
