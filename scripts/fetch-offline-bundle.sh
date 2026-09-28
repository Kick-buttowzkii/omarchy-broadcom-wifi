#!/bin/bash
# Download broadcom-wl-dkms + the headers matching the laptop's kernel, for an offline install.
# Run on any machine that has internet and pacman (Arch, Omarchy, Manjaro... any CPU architecture).
#
#   ./fetch-offline-bundle.sh <laptop kernel from `uname -r`> [output dir]
#   ./fetch-offline-bundle.sh 7.2.5-3-omarchy ./bundle
set -euo pipefail

KVER=${1:?usage: $0 <uname -r of the laptop> [output dir]}
OUT=$(realpath -m "${2:-./bundle}")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Map `uname -r` to the kernel package: 7.2.5-3-omarchy -> linux-omarchy, 7.2.5-arch1-1 -> linux
case $KVER in
  *-omarchy) HEADERS=linux-omarchy-headers ;;
  *-lts)     HEADERS=linux-lts-headers ;;
  *-zen*)    HEADERS=linux-zen-headers ;;
  *-hardened*) HEADERS=linux-hardened-headers ;;
  *)         HEADERS=linux-headers ;;
esac

mkdir -p "$WORK/db" "$OUT"
cat > "$WORK/pacman.conf" <<EOF
[options]
Architecture = x86_64
DBPath = $WORK/db/
CacheDir = $OUT/
SigLevel = Never
[core]
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
[extra]
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
[omarchy]
Server = https://pkgs.omarchy.org/stable/\$arch
EOF

P=(pacman --config "$WORK/pacman.conf")
fakeroot "${P[@]}" -Sy >/dev/null

# The headers package version must match the running kernel exactly, or DKMS cannot build.
want=$(sed -E 's/-(omarchy|lts|zen|hardened)$//; s/-arch/.arch/' <<<"$KVER")
have=$("${P[@]}" -Si "$HEADERS" | awk '/^Version/ {print $3}')
if [[ ${have#*:} != "$want"* ]]; then
  echo "WARNING: repo has $HEADERS $have but the laptop runs $KVER." >&2
  if [[ $HEADERS == linux-omarchy-headers ]]; then
    echo "Omarchy's repo lists only the current kernel: update the laptop first (e.g. over USB tethering)." >&2
  else
    echo "Fetch the matching headers from https://archive.archlinux.org/packages/l/$HEADERS/" >&2
  fi
fi

fakeroot "${P[@]}" -Sw --noconfirm --nodeps --nodeps \
  broadcom-wl-dkms dkms "$HEADERS" pahole xxhash >/dev/null

# FAT32 USB sticks reject ':' (epoch) in filenames; pacman reads the version from inside the file.
for f in "$OUT"/*:*; do [[ -e $f ]] && mv "$f" "${f//[0-9]:/}"; done
rm -f "$OUT"/*.sig

echo "Bundle for $KVER in $OUT:"
ls -1sh "$OUT"
