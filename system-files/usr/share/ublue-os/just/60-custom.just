# babazzite recipes, picked up by Bazzite's ujust (import? 60-custom.just).

# Create or recreate the development distrobox (toolchains, -devel packages)
[group('babazzite')]
devbox:
    distrobox assemble create --file /usr/share/babazzite/distrobox/dev.ini
