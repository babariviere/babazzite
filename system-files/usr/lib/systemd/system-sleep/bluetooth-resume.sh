#!/usr/bin/bash
# Re-enable the Bluetooth adapter after resume.
#
# The RTL8852BE combo card's hci0 sometimes stays powered off after a
# suspend/resume cycle even with USB autosuspend disabled, requiring a manual
# power-on. systemd runs scripts in this directory with "pre"/"post" plus the
# sleep mode, so we only act on resume ("post").
#
# After resume the RTL8852 USB device re-enumerates and its controller takes
# ~1s to re-register with bluetoothd, during which /org/bluez/hci0 does not
# exist yet. Drive the BlueZ D-Bus property directly (bluetoothctl is
# unreliable in non-interactive mode) and retry until the adapter appears.
# Bounded so a genuinely absent adapter doesn't hang the hook forever.

case "$1" in
    post)
        for _ in $(seq 1 30); do
            if busctl set-property org.bluez /org/bluez/hci0 \
                org.bluez.Adapter1 Powered b true 2>/dev/null; then
                exit 0
            fi
            sleep 0.5
        done
        exit 1
        ;;
esac
