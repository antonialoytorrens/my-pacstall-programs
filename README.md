# my-pacstall-programs

Personal [pacstall](https://github.com/pacstall/pacstall) package repository and multi-arch `.deb` builder for:

| Package | Architectures |
|---------|---------------|
| **gatus** | amd64, arm64, armhf |
| **glitchtip** | amd64 |
| **weblate** | amd64, arm64, armhf |
| **wger** | amd64, arm64, armhf |
| **fail2ban-ui** | amd64, arm64, armhf |

Pacstall cannot build for a foreign architecture by itself. Builds run under Docker Buildx with `--platform` (native runners or QEMU).

## Build locally

```bash
make help
make gatus-amd64
make glitchtip-amd64
make weblate-arm64          # needs buildx + arm64 or QEMU
make docker-wger-armhf      # kiwi-style: compose + DOCKER_PLATFORM
make wger-ubuntu-26.04      # local Ubuntu 26.04 build (not CI)
```

`make wger-ubuntu-26.04` builds the wger `.deb` with pacstall on **Ubuntu 26.04** (Resolute) so Ubuntu package names (e.g. `libjpeg-turbo8`) can be checked. Release builds stay on Debian trixie (`make wger-amd64` and CI).

Foreign-arch builds need QEMU binfmt once:

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

## CI / GitHub Releases

Push to `master` builds changed packages (path filters) and publishes a **prerelease** per package. Tags are prefixed with the package name, e.g. `gatus-5.36.0-20260906120000`, so you can install/test from Releases before promoting to your apt repo.

A daily workflow keeps the **3** newest prereleases **per package** and deletes the rest (stable releases are never touched).

## reprepro

After testing a prerelease, add each `.deb` to your reprepro repository. Architecture is taken from the package (`Architecture:`); there is no separate arch flag on `includedeb`:

```bash
reprepro -b /path/to/repo includedeb <codename> ./gatus_5.36.0_amd64.deb
reprepro -b /path/to/repo includedeb <codename> ./gatus_5.36.0_arm64.deb
reprepro -b /path/to/repo includedeb <codename> ./gatus_5.36.0_armhf.deb
reprepro -b /path/to/repo includedeb <codename> ./gatus-pgsql_5.36.0_all.deb
reprepro -b /path/to/repo includedeb <codename> ./gatus-sqlite_5.36.0_all.deb
reprepro -b /path/to/repo export
```

Alternatively, `reprepro include <codename> foo.changes` if you have a `.changes` that lists several architectures.

## Layout

```
packages/<name>/     # pacscripts and packaging files (+ VERSION)
docker/<name>/       # one Dockerfile per package (Debian trixie builder)
                     # wger also has Dockerfile.ubuntu-26.04 (local only)
Makefile             # multi-arch targets (kiwi-style docker-*)
scripts/             # publish / version-check / prerelease cleanup
```

Bump `packages/<name>/VERSION` and `pkgver` in the pacscript when updating.
