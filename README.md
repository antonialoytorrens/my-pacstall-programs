# my-pacstall-programs

Personal [pacstall](https://github.com/pacstall/pacstall) package repository and multi-arch `.deb` builder.

## Build locally

Builds on Debian 13 by default.

```bash
make help
make gatus-amd64
make glitchtip-amd64
make weblate-arm64              # needs buildx + arm64 or QEMU
make docker-wger-armhf          # via docker compose
make wger-ubuntu-26.04-amd64    # build on Ubuntu 26.04
```

Foreign-arch builds need QEMU binfmt once:

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

## Add a package

* Create `packages/<name>/` with `<name>.pacscript` (and packaging files).

Optional: add `name=<anitya_id>` to [`anitya.cfg`](anitya.cfg).

