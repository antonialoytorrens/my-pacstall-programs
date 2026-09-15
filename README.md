# my-pacstall-programs

Personal [pacstall](https://github.com/pacstall/pacstall) package repository and multi-arch `.deb` builder.

A package is anything with:

- `packages/<name>/<name>.pacscript`

Shared Dockerfiles live in `docker/` (`Dockerfile` = Debian 13 / trixie, plus `Dockerfile.<distro>-<release>`). They are rendered from `docker/Dockerfile.in` (`make dockerfiles`).

No `VERSION` file and no per-package entries in the Makefile or workflows — version is `pkgver="..."` in the pacscript; arches come from `arch=(...)`.

## Build locally

```bash
make help
make gatus-amd64
make glitchtip-amd64
make weblate-arm64              # needs buildx + arm64 or QEMU
make docker-wger-armhf          # via docker compose
make wger-ubuntu-26.04-amd64
```

Default `make <pkg>-<arch>` builds on **Debian 13 (trixie)**. Use `make <pkg>-ubuntu-26.04-<arch>` for **Ubuntu 26.04**. CI builds both.

Foreign-arch builds need QEMU binfmt once:

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

## Add a package

1. Create `packages/<name>/` with `<name>.pacscript` (and packaging files).
2. Done — `make`, CI discover, publish, and cleanup pick it up automatically.

Optional: add `name=<anitya_id>` to [`anitya.cfg`](anitya.cfg) when upstream is not on GitHub (e.g. glitchtip, weblate). GitHub packages are inferred from the pacscript.

## CI / GitHub Releases

Push to `master` builds changed packages and publishes a **prerelease** per package. Tags look like `gatus-5.36.0-20260906120000`.

Assets are tagged with distro version (not codename), e.g. `wger_2.7~debian13_amd64.deb`, `gatus_5.36.0~ubuntu26.04_amd64.deb`.

A daily workflow keeps the **3** newest prereleases **per package** (stable releases are never touched).

## reprepro

```bash
reprepro -b /path/to/repo includedeb <codename> ./gatus_5.36.0~debian13_amd64.deb
reprepro -b /path/to/repo includedeb <codename> ./wger_2.7~ubuntu26.04_amd64.deb
reprepro -b /path/to/repo export
```

## Layout

```
packages/<name>/     # pacscript + packaging files
docker/              # shared Dockerfile.in → Dockerfile, Dockerfile.ubuntu-26.04
scripts/discover.sh  # package discovery / matrices / pkgver
Makefile             # generic targets from discover.sh
```

Bump `pkgver` in the pacscript when updating.
