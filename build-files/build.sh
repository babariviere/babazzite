#!/usr/bin/env bash

set -ouex pipefail

#### Optfix (pre): make /opt writable during the build
# Anything an RPM drops into /opt would otherwise land in /var/opt, which is
# per-machine state (not part of the image) and is wiped on bootc deploys.
# Move the real payload under /usr/lib/opt (immutable, in the image) and point
# /opt at it for the duration of the build. This mirrors BlueBuild's built-in
# optfix (pre_build.sh / post_build.sh).
# https://github.com/coreos/rpm-ostree/issues/233
# https://bootc-dev.github.io/bootc/filesystem.html#more-generally-dealing-with-opt
optfix_dir="/usr/lib/opt"
mkdir -p "$optfix_dir"
if [ -d /opt ] || [ -h /opt ]; then
    if [ -n "$(ls -A /opt/ 2>/dev/null)" ]; then
        mv /opt/* "$optfix_dir"
    fi
    rm -fr /opt
fi
ln -fs "$optfix_dir" /opt

#### Third-party repos
# Enabled only for the duration of the build and disabled again at the end, so
# the shipped image only carries the repos Bazzite itself enables. Bazzite ships
# terra disabled (only terra-mesa is on); 1password, ghostty and the gamescope
# session packages come from it.
coprs=(
    gmaglione/podman-bootc
    imput/helium
)

for copr in "${coprs[@]}"; do
    dnf5 -y copr enable "$copr"
done
dnf5 -y config-manager setopt terra.enabled=1

# Punktfunk: Moonlight-compatible streaming host, installed from unom's Gitea RPM
# registry rather than the COPR: only the registry carries the punktfunk-web
# console (COPR's mock chroot has no bun). The registry has one group per Fedora
# release, so track whatever release the Bazzite base is on.
# https://docs.punktfunk.unom.io/docs/bazzite
fedora_version="$(rpm -E %fedora)"
cat >/etc/yum.repos.d/punktfunk.repo <<EOF
[punktfunk]
name=punktfunk (unom)
baseurl=https://git.unom.io/api/packages/unom/rpm/fedora-${fedora_version}
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://git.unom.io/api/packages/unom/rpm/repository.key
       https://git.unom.io/api/packages/unom/generic/punktfunk-keys/1/RPM-GPG-KEY-punktfunk
EOF

#### Install packages

grep -Ev '^[[:space:]]*(#|$)' /ctx/packages | xargs dnf5 install -y

# Darkly (Qt application style) is only published as per-release RPMs on GitHub.
darkly_version=0.5.40
dnf5 install -y "https://github.com/Bali10050/Darkly/releases/download/v${darkly_version}/darkly-${darkly_version}.fc${fedora_version}.x86_64.rpm"

#### Papirus: Catppuccin Mocha Mauve folders
# Adds the cat-* folder colours to Papirus and switches Papirus-Dark to mauve,
# matching the Plasma colour scheme set up in the dotfiles. Pinned commits.
papirus_tmp="$(mktemp -d)"
curl -fsSL https://github.com/catppuccin/papirus-folders/archive/f83671d17ea67e335b34f8028a7e6d78bca735d7.tar.gz |
    tar -xz -C "$papirus_tmp" --strip-components=1
cp -r "$papirus_tmp"/src/* /usr/share/icons/Papirus/
curl -fsSL -o "$papirus_tmp/papirus-folders" \
    https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/0f838ee5679229e3a3e97e3b333c222c9e9615b4/papirus-folders
bash "$papirus_tmp/papirus-folders" -C cat-mocha-mauve --theme Papirus-Dark
rm -rf "$papirus_tmp"

#### Services

systemctl enable podman.socket
systemctl enable -f --global podman.socket
systemctl enable libvirtd

# Punktfunk runs as systemd *user* units inside the graphical session (the host
# needs the session's compositor, PipeWire graph and /dev/uinput). Enabling them
# globally means every user gets them on login; the udev rule ships with the RPM.
# Streaming still needs the user in the `input` group:
#     ujust add-user-to-input-group
systemctl enable -f --global punktfunk-host
systemctl enable -f --global punktfunk-web

# Firewall: the punktfunk RPM ships the service definitions, so this can run here.
# punktfunk-gamestream (the Moonlight-compatible port set) is deliberately NOT
# opened: this host serves the native punktfunk/1 clients only, and the
# GameStream planes carry plain-HTTP pairing plus legacy GCM nonce reuse.
firewall-offline-cmd --add-service=punktfunk-native
firewall-offline-cmd --add-service=punktfunk-web

# The punktfunk media DATA plane binds an EPHEMERAL UDP port per session, which
# punktfunk-native deliberately does not cover, so inbound hole-punch packets are
# dropped ("no hole-punch reached this host's data port" in the host log) and the
# client falls back to an unconfirmed return path. Pin it to one port with
#     PUNKTFUNK_DATA_PORT=9778
# in ~/.config/punktfunk/host.env, and open only that port here, alongside the
# 9777 QUIC control port that punktfunk-native already covers.
firewall-offline-cmd --add-port=9778/udp

#### Image signature policy
# CI signs every pushed digest with cosign (cosign.pub / SIGNING_SECRET). Require
# that signature for this repository, so a deployment switched with
# `bootc switch --enforce-container-sigpolicy` verifies every upgrade.
install -Dm644 /ctx/cosign.pub /etc/pki/containers/babazzite.pub
install -Dm644 /dev/stdin /etc/containers/registries.d/babazzite.yaml <<'EOF'
docker:
  ghcr.io/babariviere/babazzite:
    use-sigstore-attachments: true
EOF
policy=/etc/containers/policy.json
jq '.transports.docker["ghcr.io/babariviere/babazzite"] = [{
        "type": "sigstoreSigned",
        "keyPath": "/etc/pki/containers/babazzite.pub",
        "signedIdentity": { "type": "matchRepository" }
    }]' "$policy" >/tmp/policy.json
install -m644 /tmp/policy.json "$policy"

#### Disable build-only repos

for copr in "${coprs[@]}"; do
    dnf5 -y copr disable "$copr"
done
dnf5 -y config-manager setopt punktfunk.enabled=0
dnf5 -y config-manager setopt terra.enabled=0

#### Optfix (post): recreate /opt/<name> symlinks on the live system
# Generate a tmpfiles.d entry for each payload under /usr/lib/opt so that
# /opt/<name> -> /usr/lib/opt/<name> is created on boot, then restore the
# stock /opt -> /var/opt symlink for the final image.
mkdir -p /usr/lib/tmpfiles.d
shopt -s nullglob
for optdir in "$optfix_dir"/*/; do
    opt=$(basename "$optdir")
    echo "L+ /opt/${opt} - - - - ${optfix_dir}/${opt}" >"/usr/lib/tmpfiles.d/99-optfix-${opt}.conf"
done
shopt -u nullglob

rm -fr /opt
ln -fs /var/opt /opt
