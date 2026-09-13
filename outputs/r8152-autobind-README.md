# Persistent Realtek driver on the O22 TV

The script starts a small background watcher through Homebrew Channel's existing
boot hook. Every two seconds it checks for supported Realtek USB Ethernet
adapters, including OEM VID/PID pairs from the tested module. It handles devices
already connected at startup and devices plugged in later, on any USB port.

It loads `/home/root/r8152_oot-o22.ko` and takes eligible interfaces away from
`cdc_ncm` or the built-in `r8152`. It also tries eligible unbound interfaces.
Interfaces already using `r8152_oot` and unrelated USB devices are left alone.
No udev rules, root-filesystem changes, module blacklists, or network-service
changes are needed. This is a periodic watcher, not a udev event handler.

## Requirements and guards

- Root shell on this LG OLED65C41LA / O22 TV.
- Running kernel exactly `5.4.268-329.ptl4tv.5`.
- The successfully tested, unmodified module at `/home/root/r8152_oot-o22.ko`.
  The script checks its SHA-256, not just the easily changed filename/vermagic.
- Homebrew Channel root startup for automatic boot execution. The installer
  checks for `/var/lib/webosbrew/startup.sh` or `/tmp/webosbrew_startup`. If it
  cannot find either, it refuses installation; manual `start` still works.
- Standard webOS shell tools, including `flock`, `nohup`, `sha256sum`, `readlink`,
  and `insmod`. The script checks these before loading anything. Homebrew's
  own startup script uses `flock`.

Known module SHA-256:
`fe1691622747c106af44f7834675ec75ca3327a797c6bbec394e2998db66e8cb`

Expected module srcversion: `F80F21800B80AE6B3192A62`. If `r8152_oot` is already
loaded, the script checks this too, to catch an earlier/different build.

Do not strip or substitute the module without updating and reviewing these
guards. A firmware/kernel update intentionally stops this automation until
compatibility is reassessed. There are no force-loading flags.

## 1. Upload the script from WSL

The module is already on the TV, so only upload the script. Substitute the TV's
current IP if it is no longer `192.168.1.2`.

```sh
scp -O /mnt/c/Users/user/Documents/Codex/2026-09-12/i-have-a-lg-oled-tv/outputs/r8152-autobind.sh root@192.168.1.2:/home/root/r8152-autobind.sh
```

The supplied script has Unix LF line endings. Preserve them if editing on Windows.

## 2. Test manually on the TV before installing the boot hook

Prefer Wi-Fi or the built-in NIC for the control/SSH connection during initial
testing. Taking over an active CDC interface briefly removes its network device;
SSH can disconnect and its DHCP address/interface name may change. The background
worker survives SSH disconnection. webOS retains responsibility for DHCP/routes.

```sh
sh -n /home/root/r8152-autobind.sh && chmod 755 /home/root/r8152-autobind.sh
sh /home/root/r8152-autobind.sh start
sleep 4
sh /home/root/r8152-autobind.sh status
```

The already-working `r8152_oot` adapter should not be interrupted. To test hotplug,
unplug and reconnect the USB adapter, allow a few seconds, then reconnect SSH if
needed. Run `status` again; it should show the current Ethernet interface using
`r8152_oot`. You do not need to specify `eth1`, `eth2`, `5-1`, or `7-1`.

If something fails, collect:

```sh
sh /home/root/r8152-autobind.sh status
dmesg | tail -80
```

Logs are in RAM: `/tmp/r8152-autobind/events.log` (rotated at about 64 KiB, with
one backup) and `/tmp/r8152-autobind/startup.log`. They are lost on a full reboot.
`Worker launch requested` means the asynchronous worker was started, not that
loading or binding has already succeeded. Use `status` to check the result.

## 3. Enable boot startup after the manual test succeeds

```sh
sh /home/root/r8152-autobind.sh install
```

This creates only the symlink:

```text
/var/lib/webosbrew/init.d/90-r8152-oot -> /home/root/r8152-autobind.sh
```

The hook name intentionally has no `.sh` extension: it must be accepted by
`run-parts`. With no argument, the script starts the worker in the background and
returns promptly. Installation does not reboot the TV and does not itself start
another worker. Repeated `start` requests are protected by a single-worker lock.

After a full TV reboot, verify with `status`. A normal standby cycle / Quick Start+
may not reboot the kernel; in that case the existing watcher should continue.
Resume/hotplug behavior still needs checking on the actual TV. This does not add
an independent service supervisor: if the worker unexpectedly exits, `status`
will show it stopped; use `start` or a full reboot to restart it.

## Stop, disable, and remove

Stop the current worker, leaving the boot hook installed:

```sh
sh /home/root/r8152-autobind.sh stop
```

Stop and disable it across future boots:

```sh
sh /home/root/r8152-autobind.sh disable
```

This creates `/home/root/r8152-autobind.disabled`. To enable it again:

```sh
rm -f /home/root/r8152-autobind.disabled
sh /home/root/r8152-autobind.sh start
```

Remove automatic startup entirely:

```sh
sh /home/root/r8152-autobind.sh uninstall
```

Uninstall removes only this script's boot-hook symlink and requests worker stop.
It preserves both the script and the `.ko`. Stop/disable/uninstall never unload
the module or deliberately disconnect an already-working adapter. An in-flight
takeover can finish before the worker exits. Wait a few seconds before restarting.

Once disabled or uninstalled, a full reboot returns to normal driver selection.
Unplugging alone is not a guaranteed return to CDC: the external module remains
loaded until reboot. If USB networking becomes unavailable, use Wi-Fi or the
built-in NIC to disable the script; do not delete or rewrite firmware partitions.

## Binding details and limitations

- This module can change USB configuration asynchronously from CDC mode to vendor
  mode, replacing e.g. `5-1:2.0` with `5-1:1.0`. A sysfs bind write can return an
  error even though that transition subsequently succeeds. The watcher rescans
  the entire device instead of assuming the old interface name remains valid.
- Only vendor-class interfaces or matching CDC NCM/ECM control classes are
  eligible. It does not detach CDC data interfaces individually. A control
  interface owned by a driver other than `cdc_ncm`, built-in `r8152`, or no driver
  is left alone (including `cdc_ether`).
- A physical enumeration gets at most three script-issued takeover attempts,
  tracked across configuration changes. A new enumeration or observed unplug
  resets that budget. This limit does not disable the kernel's own probing.
- Failed binding gets a best-effort CDC rebind only if the original interface is
  still present and unbound. A later queued configuration switch may supersede
  it. There is no forced configuration rollback or USB reset loop.
- Kernel panics/hangs cannot be made safe by a shell script. This uses the module
  already tested with both adapters; first boot/hotplug and standby tests remain
  necessary. Do not depend solely on Homebrew's startup failsafe to catch faults
  occurring later in a background worker.

## Validation and references

The script was statically reviewed against the actual Realtek and WM kernel
sources; its allowlist, module fingerprint and release guard were checked against
the successful build artifacts. It has **not yet been executed on the TV**.
Local WSL and the bundled POSIX shell were blocked by the desktop sandbox, so
`sh -n` and the manual hotplug test above are part of first deployment.

The boot hook and synchronous `run-parts` behavior are documented in the
[Homebrew Channel startup implementation](https://github.com/webosbrew/webos-homebrew-channel/blob/main/services/startup.sh)
and the [webOS Homebrew startup-hook documentation](https://www.webosbrew.org/pages/filesystem-overlays).
