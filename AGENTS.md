# AGENTS.md

## What this is

babazzite is a custom [bootc](https://bootc-dev.github.io/bootc/) OS image: a
personal derivation of [Bazzite](https://bazzite.gg/) (`ghcr.io/ublue-os/bazzite-gnome:unstable`)
tweaked to run the [niri](https://github.com/YaLTeR/niri) Wayland compositor.
It is built from a `Containerfile`, published to GHCR by GitHub Actions, and
installed/upgraded on real machines via `bootc`.

This is NOT a regular application repo. There is no app code to run locally.
The "build" produces an OCI container image that doubles as a bootable OS.

## Layout

- `Containerfile` - image definition. Bases on Bazzite, copies `system-files/usr`
  into `/usr`, runs `build-files/build.sh`, then lints with `bootc container lint`.
- `build-files/build.sh` - the customization script run during build (enable COPR
  repos, install packages, relocate `/opt` payloads, enable systemd units).
- `build-files/packages` - newline-separated list of RPMs to install, with comment
  sections. Commented (`#`) lines are intentionally disabled, not deletions.
- `system-files/usr/...` - files baked into the image at their final paths
  (systemd units, udev rules, sleep hooks).
- `disk-config/disk.toml`, `disk-config/iso.toml` - bootc-image-builder configs
  for generating qcow2/raw/iso disk images.
- `Justfile` - all build/run/lint/format recipes (upstream template, mostly
  untouched).
- `.github/workflows/build.yml` - builds, signs (cosign), and pushes to GHCR.
- `.github/workflows/build-disk.yml` - generates disk images.
- `cosign.pub` - public signing key. Never commit `cosign.key`/private keys.

## Common tasks

- Add/remove a package: edit `build-files/packages`. Keep it grouped under the
  existing comment headers. Prefer commenting out over deleting when it may come back.
- Enable a COPR/repo or run install-time logic: edit `build-files/build.sh`.
- Ship a config/systemd unit/udev rule: drop it under `system-files/usr/...` at
  its real absolute path (minus the `system-files` prefix).
- Anything an RPM installs into `/opt` must be relocated to `/usr/lib/opt` with a
  `tmpfiles.d` symlink, because `/opt` -> `/var/opt` is per-machine state and is
  wiped on bootc deploys. See the helium example in `build.sh`.

## Build / verify

- `just build` - build the container image with podman.
- `just build-qcow2` / `build-raw` / `build-iso` - build disk images via BIB.
- `just run-vm` - boot the built qcow2 in a VM.
- `just lint` - shellcheck all `*.sh`.
- `just format` - shfmt all `*.sh`.
- `just check` / `just fix` - check/format Justfile syntax.

Full image builds are heavy (large base image, RPM installs). Prefer letting CI
build unless a local build is specifically requested. The CI build runs
`bootc container lint` as a gate.

## Conventions

- Bash scripts use `set -ouex pipefail` / `set -eoux pipefail`. Keep that.
- Commits are conventional commits (`feat:`, `fix:`, `chore:`, `ci:`).
- Version control is `jj` (jujutsu), not git directly.
- Renovate/Dependabot pin and update GitHub Action SHAs; don't hand-edit pins.

## Don't

- Don't commit private keys (`cosign.key`).
- Don't put persistent config in `/opt`, `/var`, or `/etc` expecting it to
  survive deploys; bake it into the image under `/usr`.
- Don't start implementing changes unless explicitly asked.
