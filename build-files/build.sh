#!/usr/bin/env bash

set -ouex pipefail

repos=(
    yalter/niri
    alternateved/bleeding-emacs
    ulysg/xwayland-satellite
    wezfurlong/wezterm-nightly
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

### Install packages

grep -v '^#' /ctx/packages | xargs dnf5 install -y

#### Setup environment

cat >>/etc/environment <<EOF
PKG_CONFIG_PATH=/etc/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig
EOF

#### Setup niri deps

mkdir /usr/lib/systemd/user/niri.service.wants
ln -s /usr/lib/systemd/user/mako.service /usr/lib/systemd/user/niri.service.wants/
ln -s /usr/lib/systemd/user/waybar.service /usr/lib/systemd/user/niri.service.wants/
ln -s /usr/lib/systemd/user/swayidle.service /usr/lib/systemd/user/niri.service.wants/

#### Services

systemctl enable podman.socket
systemctl enable -f --global podman.socket


for repo in "${repos[@]}"; do
    dnf5 -y copr disable $repo
done

rm /etc/yum.repos.d/cider.repo
