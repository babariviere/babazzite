# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build-files /

# Base Image
FROM ghcr.io/ublue-os/bazzite-gnome:stable

COPY system-files/usr /usr

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    ostree container commit

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
