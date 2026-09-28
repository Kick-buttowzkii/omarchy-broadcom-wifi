#!/bin/bash
# Install the wl-guard pacman hook, the wl-rescue command, and seed the offline rescue kit.
# Run on the laptop, after Wi-Fi works: sudo ./install.sh [dir-with-.pkg.tar.zst-files]
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
cd "$(dirname "$0")"

install -Dm755 wl-guard /usr/local/bin/wl-guard
install -Dm755 wl-rescue /usr/local/bin/wl-rescue
install -Dm644 95-wl-guard.hook /etc/pacman.d/hooks/95-wl-guard.hook
install -d /var/lib/wl-guard/last-good

# Seed the rescue kit from the offline bundle you installed from, if given.
if [[ -n ${1:-} ]]; then
  install -m644 "$1"/*.pkg.tar.zst /var/lib/wl-guard/last-good/
fi

/usr/local/bin/wl-guard
echo "Rescue kit: $(ls /var/lib/wl-guard/last-good | wc -l) packages in /var/lib/wl-guard/last-good"
