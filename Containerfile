# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build-files /

# Base Image
FROM ghcr.io/ublue-os/bazzite-gnome:stable

# Layer 1: package installation and base setup.
# This is the expensive step; keeping it first (before COPY system-files) means
# editing a config file no longer invalidates the package-install layer.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Layer 2: system configuration files (cheap, changes often).
COPY system-files/usr /usr

# Layer 3: enable units shipped via system-files, then finalize the ostree commit.
RUN systemctl enable bootc-upgrade.timer && \
    ostree container commit

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
