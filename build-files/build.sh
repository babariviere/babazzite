#!/usr/bin/env bash

set -ouex pipefail

repos=(
    yalter/niri
    ulysg/xwayland-satellite
    gmaglione/podman-bootc
    imput/helium
)

for repo in "${repos[@]}"; do
    dnf5 -y copr enable $repo
done

curl -Lo 1password.sh https://raw.githubusercontent.com/blue-build/modules/22fe11d844763bf30bd83028970b975676fe7beb/modules/bling/installers/1password.sh

chmod +x 1password.sh
bash ./1password.sh

rm 1password.sh

rpm --import https://repo.cider.sh/RPM-GPG-KEY

tee /etc/yum.repos.d/cider.repo << 'EOF'
[cidercollective]
name=Cider Collective Repository
baseurl=https://repo.cider.sh/rpm/RPMS
enabled=1
gpgcheck=1
gpgkey=https://repo.cider.sh/RPM-GPG-KEY
EOF

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

#### Symlink /opt to /var/opt for mutable /opt content
# This ensures packages like helium-bin that install to /opt are accessible
# https://bootc-dev.github.io/bootc/filesystem.html#more-generally-dealing-with-opt
mkdir -p /var/opt
rmdir /opt 2>/dev/null || true
ln -sr /var/opt /opt

# Ensure tmpfiles.d creates this symlink on every boot
mkdir -p /usr/lib/tmpfiles.d
cat > /usr/lib/tmpfiles.d/opt.conf << 'EOF'
L! /opt - - - - /var/opt
EOF

#### Services

systemctl enable podman.socket
systemctl enable -f --global podman.socket
systemctl enable libvirtd


for repo in "${repos[@]}"; do
    dnf5 -y copr disable $repo
done

rm /etc/yum.repos.d/cider.repo
