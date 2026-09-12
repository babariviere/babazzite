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
    if ls -A /opt/* 2>/dev/null; then
        mv /opt/* "$optfix_dir"
    fi
    rm -fr /opt
fi
ln -fs "$optfix_dir" /opt

repos=(
    yalter/niri
    ulysg/xwayland-satellite
    gmaglione/podman-bootc
    imput/helium
)

for repo in "${repos[@]}"; do
    dnf5 -y copr enable $repo
done

dnf5 -y config-manager setopt "terra".enabled=true

#### Punktfunk repo
# Moonlight-compatible streaming host, installed from unom's Gitea RPM registry
# rather than the COPR: only the registry carries the punktfunk-web console
# (COPR's mock chroot has no bun). The registry has one group per Fedora
# release; the Bazzite base is currently Fedora 44, so track fedora-44 (the
# "bazzite" group is the Fedora 43 build). Bump this on the next major rebase.
# https://docs.punktfunk.unom.io/docs/bazzite
cat >/etc/yum.repos.d/punktfunk.repo <<'EOF'
[punktfunk]
name=punktfunk (unom)
baseurl=https://git.unom.io/api/packages/unom/rpm/fedora-44
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://git.unom.io/api/packages/unom/rpm/repository.key
       https://git.unom.io/api/packages/unom/generic/punktfunk-keys/1/RPM-GPG-KEY-punktfunk
EOF

### Install packages

cat /etc/yum.repos.d/terra.repo

grep -v '^#' /ctx/packages | xargs dnf5 install -y

#### Setup environment

cat >>/etc/environment <<EOF
PKG_CONFIG_PATH=/etc/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig
EOF

#### Setup niri deps

mkdir /usr/lib/systemd/user/niri.service.wants
# ln -s /usr/lib/systemd/user/mako.service /usr/lib/systemd/user/niri.service.wants/

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

# Firewall: the punktfunk RPM ships the service definitions, so this can run here
# (unlike the old Wolf rule, which lived in a COPY'd system-files XML).
# punktfunk-gamestream is the Moonlight-compatible port set.
firewall-offline-cmd --add-service=punktfunk-native
firewall-offline-cmd --add-service=punktfunk-web
firewall-offline-cmd --add-service=punktfunk-gamestream


for repo in "${repos[@]}"; do
    dnf5 -y copr disable $repo
done

#### Optfix (post): recreate /opt/<name> symlinks on the live system
# Generate a tmpfiles.d entry for each payload under /usr/lib/opt so that
# /opt/<name> -> /usr/lib/opt/<name> is created on boot, then restore the
# stock /opt -> /var/opt symlink for the final image.
mkdir -p /usr/lib/tmpfiles.d
shopt -s nullglob
for optdir in "$optfix_dir"/*/; do
    opt=$(basename "$optdir")
    echo "L+ /opt/${opt} - - - - ${optfix_dir}/${opt}" > "/usr/lib/tmpfiles.d/99-optfix-${opt}.conf"
done
shopt -u nullglob

rm -fr /opt
ln -fs /var/opt /opt
