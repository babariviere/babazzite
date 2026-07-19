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

curl -Lo 1password.sh https://raw.githubusercontent.com/blue-build/modules/e415231c2ea138c607efc52e6e533e3f0b4e69ee/modules/bling/installers/1password.sh

chmod +x 1password.sh
bash ./1password.sh

rm 1password.sh

dnf5 -y config-manager setopt "terra".enabled=true

### Install packages

cat /etc/yum.repos.d/terra.repo

grep -v '^#' /ctx/packages | xargs dnf5 install -y

dnf5 group install -y c-development development-tools virtualization

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
systemctl enable bootc-upgrade.timer


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
