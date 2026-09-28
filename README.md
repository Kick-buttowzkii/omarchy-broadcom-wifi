# Broadcom Wi-Fi on Omarchy (no Ethernet needed)

A fresh [Omarchy](https://omarchy.org) install on an old laptop with a Broadcom Wi-Fi card
often has **no Wi-Fi at all**, and if you have no Ethernet cable you can't download the fix
either. This guide gets the `wl` driver working **fully offline**, then makes sure a future
kernel update can't silently break it again.

Tested on an HP laptop with a **BCM43142** (`14e4:4365`) and an Intel i5-6200U, running
Omarchy's `linux-omarchy` kernel 7.2.5 (September 2026).

## Contents

1. [Check your Wi-Fi chip](#1-check-your-wi-fi-chip)
2. [Why the prebuilt `broadcom-wl` package won't work](#2-why-the-prebuilt-broadcom-wl-package-wont-work)
3. [Build the offline bundle on another computer](#3-build-the-offline-bundle-on-another-computer)
4. [Install it on the laptop](#4-install-it-on-the-laptop)
5. [Protect it from future updates (wl-guard)](#5-protect-it-from-future-updates-wl-guard)
6. [Bonus: fix swap and hibernation on btrfs](#6-bonus-fix-swap-and-hibernation-on-btrfs)
7. [Bonus: SSH into the laptop](#7-bonus-ssh-into-the-laptop)
8. [Troubleshooting](#troubleshooting)

> **No other computer?** Try **USB tethering** first: plug an Android phone into the laptop
> and turn on *USB tethering*. Omarchy treats it as a wired connection, and you can run
> `sudo pacman -Syu broadcom-wl-dkms linux-omarchy-headers` directly, then skip to step 5.

---

## 1. Check your Wi-Fi chip

```bash
lspci -nnk | grep -A3 -i network
```

Some Broadcom chips work with drivers already built into Linux (`b43`, `brcmsmac`,
`brcmfmac`). If yours shows one of those under *Kernel modules* and Wi-Fi still fails,
you probably need firmware (`linux-firmware-broadcom`), not this guide.

This guide is for chips that need Broadcom's proprietary **`wl`** driver, for example
BCM43142, BCM4311/4312/4321/4322, BCM43224/43225/43227/43228, BCM4331, BCM4352 and BCM4360.

Also note your kernel version, because everything has to match it exactly:

```bash
uname -r        # e.g. 7.2.5-3-omarchy
```

## 2. Why the prebuilt `broadcom-wl` package won't work

Arch used to ship `broadcom-wl`, with the driver pre-compiled for one exact Arch kernel.

- Arch **dropped it** from the repos. Only old builds remain in the
  [Arch Linux Archive](https://archive.archlinux.org/packages/b/broadcom-wl/), and the last
  one targets kernel 7.1.11.
- Omarchy runs its **own kernel** (`linux-omarchy`, `uname -r` ends in `-omarchy`), so no
  prebuilt Arch module will load on it anyway.
- Reflashing a newer Omarchy ISO **doesn't help**. It installs the same custom kernel.

The fix is **`broadcom-wl-dkms`**: it ships the driver source and compiles it for *your*
kernel on the laptop itself. For that you need the **kernel headers that exactly match**
your kernel (`linux-omarchy-headers`, from Omarchy's own repo).

## 3. Build the offline bundle on another computer

On any computer with internet and `pacman` (another Arch/Omarchy machine, a VM, even an
ARM one), run:

```bash
git clone https://github.com/Kick-buttowzkii/omarchy-broadcom-wifi
cd omarchy-broadcom-wifi
./scripts/fetch-offline-bundle.sh 7.2.5-3-omarchy ./bundle     # use YOUR `uname -r`
```

That gives you 5 small packages (about 90 MB, almost all of it the headers):

| Package | Why |
|---|---|
| `broadcom-wl-dkms` | The driver source; also blacklists the conflicting `b43`/`bcma`/`ssb` drivers |
| `dkms` | Builds the driver for your kernel, and rebuilds it on every kernel update |
| `linux-omarchy-headers` | Must match `uname -r` exactly |
| `pahole`, `xxhash` | Needed by the headers to build modules |

The script warns you if the repo's headers are newer than the laptop's kernel. If you see
that warning, the laptop's kernel is out of date, and the easiest fix is USB tethering
(see the note at the top).

No `pacman` handy? Download the same files by hand, in a browser, from
<https://archlinux.org/packages/> (`broadcom-wl-dkms`, `dkms`, `pahole`, `xxhash`) and
`https://pkgs.omarchy.org/stable/x86_64/` (`linux-omarchy-headers`, same version as your kernel).

Copy the `bundle` folder to a USB stick.

## 4. Install it on the laptop

1. Check the compiler is there (Omarchy ships it):

   ```bash
   gcc --version && make --version
   ```

   If either is missing, don't grab a newer `gcc` from today's repos, because a
   half-updated system can break. Use USB tethering instead.

2. Install everything from the USB stick. DKMS builds the driver during the install:

   ```bash
   cd /path/to/bundle
   sudo pacman -U --needed *.pkg.tar.zst
   dkms status     # should say: broadcom-wl/..., <your kernel>, x86_64: installed
   ```

3. Load the driver (or just reboot) and connect:

   ```bash
   sudo modprobe wl
   iwctl station wlan0 connect "YourNetwork"
   ip -4 addr show wlan0     # you should now have a 192.168.x.x address
   ```

## 5. Protect it from future updates (wl-guard)

DKMS rebuilds `wl` automatically on every kernel update, as long as the kernel and its
headers update together (a normal `omarchy-update` does that). But if the driver ever fails
to compile against a new kernel, you'd only find out after rebooting, with no internet.

`wl-guard` is a small pacman hook that catches that *before* you reboot:

- After every update to the kernel, its headers, `dkms` or `broadcom-wl-dkms`, it checks
  that `wl` was built for every installed kernel, and retries the build if not.
- **If it fails:** you get a red warning in the terminal, a desktop notification, and a
  line in `/var/lib/wl-guard/failures.log`: *Do NOT reboot yet. Run: sudo wl-rescue*.
- **If it works:** it saves the working kernel, headers and driver packages as an offline
  rescue kit in `/var/lib/wl-guard/last-good/`.
- `sudo wl-rescue` reinstalls that rescue kit with **no internet**, then you reboot.

Install it, seeding the rescue kit with your bundle. Add the kernel package itself
(`linux-omarchy-<version>-x86_64.pkg.tar.zst`, from the same Omarchy repo) to the bundle
if you want the kit to be able to roll the kernel back too:

```bash
sudo ./wl-guard/install.sh /path/to/bundle
```

You should see `wl-guard: wl OK for all kernels.`

**If Wi-Fi ever breaks after an update, in this order:**

1. Saw the red warning? **Don't reboot.** Run `sudo wl-rescue` first.
2. Already rebooted with no Wi-Fi? `sudo wl-rescue`, then `sudo reboot`.
3. Last resort: pick the pre-update snapshot in the boot menu. `omarchy-update` takes one
   before every update, so update with **`omarchy-update`**, not plain `pacman -Syu`.

## 6. Bonus: fix swap and hibernation on btrfs

Trying to make a bigger swap file with `dd` or `fallocate` on Omarchy fails with
`swapon: Invalid argument`. The root filesystem is btrfs with zstd compression and
copy-on-write, and btrfs can't swap to a file like that.

```bash
sudo ./scripts/rebuild-swap.sh 16g
```

It recreates `/swap/swapfile` with `btrfs filesystem mkswapfile`, which sets it up
properly. If hibernation is set up, it also updates the `resume_offset` (where the file
sits on disk) and rebuilds the boot image. Without that step, hibernation breaks the
moment the swap file moves. If you tried `dd` before, delete the broken file it left:
`sudo rm /swapfile`.

How big? For **hibernation** you need at least as much swap as RAM. Anything beyond that
is overflow for when you run out of RAM. It's slow, but it stops things crashing.

Test it:

```bash
systemctl hibernate      # saves everything to disk and powers off
# press power, unlock the disk; your apps should be exactly where you left them
uptime -s                # unchanged boot time = it restored, not rebooted
```

> **Sleep vs hibernate:** *sleep* keeps everything in RAM on a trickle of battery (instant
> wake, but it drains). *Hibernate* writes RAM to the swap file and turns the laptop **fully
> off** (zero battery use, a slightly slower wake).

## 7. Bonus: SSH into the laptop

Omarchy doesn't run an SSH server by default, and its firewall blocks incoming connections:

```bash
sudo systemctl enable --now sshd
sudo ufw allow ssh
```

Copy your key over from the other machine (`ssh-copy-id user@laptop-ip`), then turn off
password logins:

```bash
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' \
  | sudo tee /etc/ssh/sshd_config.d/10-key-only.conf
sudo sshd -t && sudo systemctl reload sshd
```

And give the account a strong password (`passwd`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ip -4 addr` shows only `127.0.0.1` | Wi-Fi isn't connected: `iwctl station wlan0 connect "SSID"` |
| `dkms status` shows nothing / `added` only | Headers don't match `uname -r`. Get the exact `linux-omarchy-headers` version |
| `modprobe wl` gives *Key was rejected by service* | Secure Boot is on. Disable it, or sign the module |
| `ssh: connect ... timed out` | `sshd` isn't running or `ufw` is blocking it (step 7) |
| `ssh-copy-id` fails with `ssh_askpass: No such file` | Run it in a real terminal, not through a non-interactive shell |
| `swapon: Invalid argument` | The swap file is on compressed/CoW btrfs. Use `scripts/rebuild-swap.sh` |
| `kmod: ignoring bad line starting with 'blacklst'` | Typo in `/etc/modprobe.d/blacklist.conf`. It should say `blacklist` |

## License

MIT. The scripts are yours to copy. `broadcom-wl` itself is Broadcom's proprietary driver
under its own license; this repo doesn't redistribute it.
