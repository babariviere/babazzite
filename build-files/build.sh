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

#### Relocate /opt payloads into /usr so they survive bootc deploys
# /opt -> /var/opt on bazzite, and /var is per-machine state (not part of the
# image), so anything an RPM drops into /opt gets thrown away at deploy time.
# Move the real content under /usr/lib/opt (immutable, in the image) and
# recreate the /opt entry with tmpfiles.d on every boot.
# https://bootc-dev.github.io/bootc/filesystem.html#more-generally-dealing-with-opt
mkdir -p /usr/lib/opt
mv /opt/helium /usr/lib/opt/helium

mkdir -p /usr/lib/tmpfiles.d
cat > /usr/lib/tmpfiles.d/opt-helium.conf << 'EOF'
L+ /var/opt/helium - - - - /usr/lib/opt/helium
EOF

#### Services

systemctl enable podman.socket
systemctl enable -f --global podman.socket
systemctl enable libvirtd


for repo in "${repos[@]}"; do
    dnf5 -y copr disable $repo
done
