# babazzite

A personal [bootc](https://bootc-dev.github.io/bootc/) OS image: [Bazzite](https://bazzite.gg/)
(KDE Plasma) with game mode, game streaming, and virtualization layered on top.

```
ghcr.io/babariviere/babazzite:stable
```

This is not an application repo. There is nothing to run locally. The build
produces an OCI image that doubles as a bootable operating system, published to
GHCR and deployed to real machines with `bootc`.

## What it is

The base is `ghcr.io/ublue-os/bazzite:stable`, the KDE Plasma desktop variant of
Bazzite, which brings the gaming stack (Steam, Proton, gamescope, the Bazzite
kernel with HDR patches, amdgpu tuning). Plasma is the only desktop session.
On top of it, the image bundles:

- **Game mode** via `gamescope-session` + `gamescope-session-steam`, selectable
  as its own session. Bazzite only ships this in its `-deck` images, so it is
  pulled in explicitly here.
- **Remote play** with [punktfunk](https://docs.punktfunk.unom.io/), running as
  systemd user units inside the graphical session, with firewall rules and a
  pinned data port.
- **Containers and VMs**: podman, podman-bootc, libvirt, virt-manager.
- **Devbox**: compilers, Rust, and `-devel` packages live in a distrobox
  rather than the image. `ujust devbox` creates (or recreates) it from
  `/usr/share/babazzite/distrobox/dev.ini`.
- **Automatic updates**: Bazzite's `uupd.timer` applies new images daily, and
  also updates flatpaks and distroboxes (including the devbox).
- **zram tuning**: `vm.swappiness=180` and `vm.page-cluster=0`, since swap is
  zram only.
- **Signature policy**: the image ships a `policy.json` entry requiring the
  cosign signature for `ghcr.io/babariviere/babazzite`.

## Layout

| Path | Purpose |
|---|---|
| `Containerfile` | Image definition. Three layers: packages, config files, unit enablement. |
| `build-files/build.sh` | Build-time script: enable repos, install packages, relocate `/opt`, enable units, open firewall ports, install the signature policy, disable build-only repos. |
| `build-files/packages` | Newline-separated RPM list, grouped under comment headers. |
| `system-files/usr/` | Files baked into the image at their final absolute paths, minus the `system-files` prefix. |
| `system-files/etc/` | `/etc` defaults, only for config that must live in `/etc` (e.g. sysctls that tuned must not override). |
| `disk-config/` | bootc-image-builder configs for qcow2/raw/iso output. |
| `Justfile` | Build, run, lint, format recipes. Mostly upstream template. |
| `.github/workflows/build.yml` | Builds, signs with cosign, pushes to GHCR. Runs on push and daily at 10:05 UTC. |
| `.github/workflows/lint.yml` | Runs `just lint` (shellcheck) and `just check` on pushes and PRs. |
| `.github/workflows/build-disk.yml` | Generates disk images, optionally uploaded to S3. |

The Containerfile is ordered so that the expensive package-install layer comes
before `COPY system-files/usr`. Editing a config file therefore does not
invalidate the RPM cache.

## Installing

On an existing Fedora Atomic or Bazzite system:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/babariviere/babazzite:stable
sudo systemctl reboot
```

`--enforce-container-sigpolicy` makes bootc verify the cosign signature on
every upgrade. It needs the policy shipped by the image, so when coming from
plain Bazzite, switch once without the flag, reboot, then switch again with it.

Afterwards updates are automatic via `uupd.timer`. To force one:

```bash
sudo bootc upgrade
```

To roll back to the previous deployment:

```bash
sudo bootc rollback
```

## Building locally

Full builds are heavy. CI is usually the better option, but:

```bash
just build              # build the container image with podman
just build-qcow2        # disk image via bootc-image-builder
just run-vm             # boot the qcow2 in a VM
just lint               # shellcheck
just format             # shfmt
```

## Making changes

**Add a package**: edit `build-files/packages`, keeping it under an existing
comment header. Prefer commenting out over deleting when it may come back.

**Enable a repo or run install-time logic**: edit `build-files/build.sh`.

**Ship a config file, systemd unit, or udev rule**: drop it under
`system-files/usr/...` at its real path.

**Anything landing in `/opt`** must be relocated to `/usr/lib/opt` with a
`tmpfiles.d` symlink. `/opt` is a symlink to `/var/opt`, which is per-machine
state and is wiped on deploys. `build.sh` handles this generically; see the
optfix blocks.

Version control is [jj](https://jj-vcs.github.io/jj/), not git directly.
Commits follow conventional commit format.

## Gotchas worth knowing

**The punktfunk repo follows the base's Fedora release.** `build.sh` derives the
registry group from `rpm -E %fedora`, so a rebase fails loudly if unom has not
published that release yet.

**Game mode packages are deliberate.** `gamescope-session` and
`gamescope-session-steam` exist in `packages` because Bazzite installs the
session only in its `bazzite-deck` stage. The desktop image ships the gamescope
binary (`terra-gamescope`) with nothing on top of it.

**Host apps built in the devbox may need runtime libs on the host.** The devbox
carries `-devel` packages, but binaries run on the host still need the shared
libraries there (for example `webkit2gtk4.1` for anno, listed in `packages`).

## Verification

Images are signed with cosign. `cosign.pub` at the repo root is the public key:

```bash
cosign verify --key cosign.pub ghcr.io/babariviere/babazzite:stable
```

Never commit `cosign.key` or any other private key.

## Credits

Built from the Universal Blue [image-template](https://github.com/ublue-os/image-template),
on top of [Bazzite](https://bazzite.gg/) and the rest of the
[Universal Blue](https://universal-blue.org/) stack.
