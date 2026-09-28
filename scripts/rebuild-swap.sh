#!/bin/bash
# Recreate Omarchy's btrfs swap file at a new size and keep hibernation working.
#   sudo ./rebuild-swap.sh 16g
#
# Why not dd/fallocate? On btrfs a swap file must be NOCOW, uncompressed and in one
# piece, or `swapon` fails with "Invalid argument". `btrfs filesystem mkswapfile` does it right.
# Moving the file changes its physical offset, so the hibernation `resume_offset` is updated too.
set -euo pipefail
SIZE=${1:?usage: $0 <size, e.g. 16g>}
SWAP=/swap/swapfile
RESUME_CONF=/etc/limine-entry-tool.d/resume.conf
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
[[ $(findmnt -no FSTYPE /) == btrfs ]] || { echo "Root is not btrfs; use dd + mkswap instead." >&2; exit 1; }

swapoff "$SWAP" 2>/dev/null || true
rm -f "$SWAP"
mkdir -p "$(dirname "$SWAP")"
btrfs filesystem mkswapfile --size "$SIZE" --uuid clear "$SWAP"
swapon "$SWAP"
grep -q "^$SWAP " /etc/fstab || echo "$SWAP none swap defaults,pri=0 0 0" >> /etc/fstab

OFF=$(btrfs inspect-internal map-swapfile -r "$SWAP")
echo "New resume_offset: $OFF"
if [[ -f $RESUME_CONF ]]; then
  sed -i "s/resume_offset=[0-9]*/resume_offset=$OFF/" "$RESUME_CONF"
  limine-mkinitcpio                       # rebuild the UKI + limine.conf with the new offset
  echo "$OFF" > /sys/power/resume_offset  # let this boot hibernate too, without a reboot
else
  echo "No $RESUME_CONF: hibernation is not set up, nothing else to do."
fi
swapon --show
