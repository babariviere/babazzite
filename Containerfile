# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build-files /
COPY cosign.pub /cosign.pub

# Base Image
FROM ghcr.io/ublue-os/bazzite:stable

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

# Layer 3: finalize the ostree commit.
# /run and /tmp must be empty in a bootc image, and the package installs above
# leave junk in both. Clearing them here (rather than with an extra buildah
# commit in CI) avoids rewriting the whole image a second time at build time.
RUN { find /run /tmp -mindepth 1 -xdev -delete 2>/dev/null || true; } && \
    ostree container commit

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
