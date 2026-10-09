# babazzite

A personal [bootc](https://bootc-dev.github.io/bootc/) OS image: [Bazzite](https://bazzite.gg/)
with the [niri](https://github.com/YaLTeR/niri) scrolling Wayland compositor on top.

```
ghcr.io/babariviere/babazzite:stable
```

This is not an application repo. There is nothing to run locally. The build
produces an OCI image that doubles as a bootable operating system, published to
GHCR and deployed to real machines with `bootc`.

## What it is

The base is `ghcr.io/ublue-os/bazzite:stable`, the KDE Plasma desktop variant of
Bazzite, which brings the gaming stack (Steam, Proton, gamescope, the Bazzite
kernel with HDR patches, amdgpu tuning). On top of that, babazzite layers a niri
session and the pieces a bare compositor needs to be a usable desktop: portals,
a notification path, clipboard tooling, audio, polkit, networking applets.

Both sessions ship. Plasma stays available from the login screen, and niri is
the day-to-day one.

Beyond the desktop, the image bundles:

- **Game mode** via `gamescope-session` + `gamescope-session-steam`, selectable
  as its own session. Bazzite only ships this in its `-deck` images, so it is
  pulled in explicitly here.
- **Remote play** with [punktfunk](https://docs.punktfunk.unom.io/), running as
  systemd user units inside the graphical session, with firewall rules and a
  pinned data port.
- **Containers and VMs**: podman, podman-bootc, incus, libvirt, virt-manager.
- **Dev toolchain**: compilers, Rust, and the assorted `-devel` packages needed
  by projects built on this machine.
- **Automatic updates**: `bootc-upgrade.timer` applies new images daily.

## Layout

| Path | Purpose |
|---|---|
| `Containerfile` | Image definition. Three layers: packages, config files, unit enablement. |
| `build-files/build.sh` | Build-time script: enable repos, install packages, relocate `/opt`, enable units, open firewall ports. |
| `build-files/packages` | Newline-separated RPM list, grouped under comment headers. Commented lines are deliberately disabled, not dead. |
| `system-files/usr/` | Files baked into the image at their final absolute paths, minus the `system-files` prefix. |
| `disk-config/` | bootc-image-builder configs for qcow2/raw/iso output. |
| `Justfile` | Build, run, lint, format recipes. Mostly upstream template. |
| `.github/workflows/build.yml` | Builds, signs with cosign, pushes to GHCR. Runs on push and daily at 10:05 UTC. |
| `.github/workflows/build-disk.yml` | Generates disk images, optionally uploaded to S3. |

The Containerfile is ordered so that the expensive package-install layer comes
before `COPY system-files/usr`. Editing a config file therefore does not
invalidate the RPM cache.

## Installing

On an existing Fedora Atomic or Bazzite system:

```bash
sudo bootc switch ghcr.io/babariviere/babazzite:stable
sudo systemctl reboot
```

Afterwards updates are automatic via `bootc-upgrade.timer`. To force one:

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

**The punktfunk repo is pinned to a Fedora release.** `build.sh` tracks
`fedora-44` to match the current Bazzite base. Bump it on the next major rebase.

**Game mode packages are deliberate.** `gamescope-session` and
`gamescope-session-steam` exist in `packages` because Bazzite installs the
session only in its `bazzite-deck` stage. The desktop image ships the gamescope
binary (`terra-gamescope`) with nothing on top of it.

**GPU resets kill the niri session.** niri does not currently handle
`VK_ERROR_DEVICE_LOST` / `GL_EXT_robustness`, so an amdgpu reset triggered by a
misbehaving game takes the whole session with it. Running games under the
gamescope session contains the damage to gamescope instead.

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
