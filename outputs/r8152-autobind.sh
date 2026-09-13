#!/bin/sh
# LG OLED65C41LA / O22: prefer the tested external Realtek driver.
# Install at /home/root/r8152-autobind.sh. No arguments means start.
# No firmware writes, module force flags, USB-wide policy changes, or DHCP calls.

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077

SELF=/home/root/r8152-autobind.sh
MODULE=/home/root/r8152_oot-o22.ko
DRIVER=r8152_oot
KERNEL=5.4.268-329.ptl4tv.5
MODULE_SHA256=fe1691622747c106af44f7834675ec75ca3327a797c6bbec394e2998db66e8cb
MODULE_SRCVERSION=F80F21800B80AE6B3192A62
HOOK=/var/lib/webosbrew/init.d/90-r8152-oot
DISABLED=/home/root/r8152-autobind.disabled
STATE=/tmp/r8152-autobind
USB=/sys/bus/usb/devices
DRIVERS=/sys/bus/usb/drivers
POLL=2
MAX_ATTEMPTS=3

value() {
    [ -r "$1" ] || return 1
    IFS= read -r read_value < "$1" || return 1
    printf '%s\n' "$read_value"
}

die() { printf 'r8152-autobind: %s\n' "$*" >&2; exit 1; }

init_state() {
    [ ! -L "$STATE" ] || die "Refusing symlink: $STATE"
    mkdir -p "$STATE" || die "Cannot create $STATE"
    chmod 700 "$STATE" || exit 1
}

log() {
    # RAM-only, bounded log. Only the locked worker writes it.
    if [ -f "$STATE/events.log" ] &&
       [ "$(wc -c < "$STATE/events.log")" -gt 65536 ]; then
        mv -f "$STATE/events.log" "$STATE/events.log.1"
    fi
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$STATE/events.log"
}

preflight() {
    [ "$(id -u)" = 0 ] || die 'Run as root on the TV.'
    [ "$(uname -r)" = "$KERNEL" ] || die "Kernel is not $KERNEL; refusing this module."
    for needed in flock nohup sha256sum readlink insmod; do
        command -v "$needed" >/dev/null 2>&1 || die "Missing command: $needed"
    done
    [ -r "$MODULE" ] || die "Missing $MODULE"
    checksum=$(sha256sum "$MODULE") || die 'Cannot hash the module.'
    [ "${checksum%% *}" = "$MODULE_SHA256" ] ||
        die 'Module hash differs from the successfully tested O22 build.'
    if [ -d "/sys/module/$DRIVER" ]; then
        [ "$(value "/sys/module/$DRIVER/srcversion")" = "$MODULE_SRCVERSION" ] ||
            die 'A different or unverifiable r8152_oot is already loaded. Reboot with the tested module.'
    fi
}

supported_id() {
    # Exact VID:PID pairs from this module's USB aliases, including OEM IDs.
    case "$1" in
        0bda:8050|0bda:8053|0bda:8152|0bda:8153|0bda:8155|0bda:8156|0bda:8157|0bda:815a|\
        045e:07ab|045e:07c6|045e:0927|045e:0c5e|04e8:a101|\
        17ef:304f|17ef:3052|17ef:3054|17ef:3057|17ef:3062|17ef:3069|17ef:3082|17ef:3098|\
        17ef:7205|17ef:720a|17ef:720b|17ef:720c|17ef:7214|17ef:721e|17ef:8153|17ef:a359|17ef:a387|\
        13b1:0041|0955:09ff|2357:0601|2baf:0012|0b05:1976|0b05:1d91) return 0 ;;
        *) return 1 ;;
    esac
}

supported_interface() {
    # Never operate on a CDC data interface, hub, storage interface, etc.
    class=$(value "$1/bInterfaceClass") || return 1
    case "$class" in
        ff) return 0 ;;
        02)
            subclass=$(value "$1/bInterfaceSubClass") || return 1
            protocol=$(value "$1/bInterfaceProtocol") || return 1
            case "$subclass:$protocol" in 0d:00|06:00) return 0 ;; esac
            ;;
    esac
    return 1
}

driver_of() {
    link=$(readlink "$1/driver" 2>/dev/null) || { printf 'none\n'; return; }
    printf '%s\n' "${link##*/}"
}

device_token() {
    vendor=$(value "$1/idVendor") || return 1
    product=$(value "$1/idProduct") || return 1
    bus=$(value "$1/busnum") || return 1
    number=$(value "$1/devnum") || return 1
    printf '%s:%s:%s:%s\n' "$bus" "$number" "$vendor" "$product"
}

ours_attached() {
    for check_interface in "$USB/$1":*; do
        [ -d "$check_interface" ] || continue
        [ "$(driver_of "$check_interface")" = "$DRIVER" ] && return 0
    done
    return 1
}

disable_sg_for_device() {
    # On this O22 / xHCI path, the driver's SG transmit aggregation caused a
    # TX watchdog followed by an xHCI controller death during bidirectional
    # stress.  The attribute is created by r8152_oot under the netdev, not the
    # USB interface.  Missing nodes are normal during re-enumeration.
    for check_interface in "$USB/$1":*; do
        [ -d "$check_interface" ] || continue
        [ "$(driver_of "$check_interface")" = "$DRIVER" ] || continue
        for netdev in "$check_interface"/net/*; do
            [ -d "$netdev" ] || continue
            sg_file=$netdev/rtl_adv/sg_en
            [ -r "$sg_file" ] || continue
            [ "$(value "$sg_file")" = disable ] ||
                sys_write "$sg_file" disable || :
        done
    done
}

sys_write() {
    # Kept in one place for review/testing. A vanished sysfs node is expected
    # during unplug or the driver's asynchronous configuration 2 -> 1 switch.
    (printf '%s' "$2" > "$1") 2>> "$STATE/events.log"
}

handle_device() (
    # Subshell keeps per-device variables separate from the scanner.
    device=$1
    name=${device##*/}
    case "$name" in *[!0-9.-]*|'') return ;; esac
    vid=$(value "$device/idVendor") || return
    pid=$(value "$device/idProduct") || return
    supported_id "$vid:$pid" || return
    token=$(device_token "$device") || return
    if ours_attached "$name"; then
        disable_sg_for_device "$name"
        return
    fi

    # Select just one eligible control/vendor interface per device per scan.
    selected=
    for interface in "$USB/$name":*; do
        [ -d "$interface" ] || continue
        supported_interface "$interface" || continue
        old_driver=$(driver_of "$interface")
        case "$old_driver" in
            cdc_ncm|r8152|none) selected=$interface; break ;;
            *) continue ;;
        esac
    done
    [ -n "$selected" ] || return

    attempts=0
    previous_token=
    attempt_file=$STATE/attempt-$name
    if [ -f "$attempt_file" ]; then
        read -r previous_token attempts < "$attempt_file"
    fi
    [ "$previous_token" = "$token" ] || attempts=0
    case "$attempts" in ''|*[!0-9]*) attempts=0 ;; esac
    [ "$attempts" -lt "$MAX_ATTEMPTS" ] || return
    attempts=$((attempts + 1))
    printf '%s %s\n' "$token" "$attempts" > "$attempt_file"

    # Disabling prevents a new takeover. If one has already unbound a device,
    # let its short bind/fallback sequence finish to avoid stranding the NIC.
    [ ! -e "$DISABLED" ] || return
    [ "$(device_token "$device")" = "$token" ] || return
    [ "$(driver_of "$selected")" = "$old_driver" ] || return
    interface_name=${selected##*/}
    log "$name ($vid:$pid): attempt $attempts/$MAX_ATTEMPTS, $interface_name $old_driver -> $DRIVER"

    if [ "$old_driver" != none ]; then
        if ! sys_write "$DRIVERS/$old_driver/unbind" "$interface_name"; then
            log "$name: unbind did not complete (possibly unplugged); no bind attempted."
            return
        fi
    fi
    [ "$(device_token "$device")" = "$token" ] || return
    if [ -d "$selected" ] && [ "$(driver_of "$selected")" = none ]; then
        # ENODEV here can still mean success: vendor-mode switching is async.
        sys_write "$DRIVERS/$DRIVER/bind" "$interface_name" || :
    fi
    sleep 1
    [ "$(device_token "$device")" = "$token" ] || return
    if ours_attached "$name"; then
        disable_sg_for_device "$name"
        log "$name: attached to $DRIVER. Network setup remains with webOS."
        return
    fi

    # Best-effort fallback only if the original CDC control interface still
    # exists unbound. Never force USB configuration numbers or reset devices.
    if [ "$old_driver" = cdc_ncm ] && [ -d "$selected" ] &&
       [ "$(driver_of "$selected")" = none ]; then
        if sys_write "$DRIVERS/cdc_ncm/bind" "$interface_name"; then
            log "$name: restored cdc_ncm on the unchanged interface."
        fi
    fi
    if [ "$attempts" -ge "$MAX_ATTEMPTS" ]; then
        log "$name: attempt limit reached; inspect dmesg. Unplug/replug to retry."
    else
        log "$name: not attached yet; will rescan current interfaces."
    fi
)

scan() {
    for device_path in "$USB"/*; do
        [ -r "$device_path/idVendor" ] || continue
        handle_device "$device_path"
    done
    # Forget physically absent devices, but not an interface configuration change.
    for record in "$STATE"/attempt-*; do
        [ -f "$record" ] || continue
        record_name=${record##*/attempt-}
        [ -d "$USB/$record_name" ] || rm -f "$record"
    done
}

is_running() {
    worker_pid=$(value "$STATE/pid") || return 1
    case "$worker_pid" in ''|*[!0-9]*) return 1 ;; esac
    [ "$worker_pid" -gt 1 ] || return 1
    kill -0 "$worker_pid" 2>/dev/null || return 1
    # Validate identity before using this PID for status or termination.
    [ -r "/proc/$worker_pid/cmdline" ] || return 1
    tr '\000' '\n' < "/proc/$worker_pid/cmdline" | grep -Fxq "$SELF"
}

cleanup() {
    [ "$(value "$STATE/pid")" = "$$" ] && rm -f "$STATE/pid"
    log 'Worker stopped; loaded module and existing bindings left untouched.'
}

run_worker() {
    init_state
    exec 9> "$STATE/lock"
    flock -n 9 || exit 0
    printf '%s\n' "$$" > "$STATE/pid"
    trap cleanup 0
    trap 'exit 0' TERM INT
    trap '' HUP
    [ ! -e "$DISABLED" ] || exit 0
    preflight
    log "Worker started, kernel $KERNEL, scan interval ${POLL}s."
    if [ ! -d "$DRIVERS/$DRIVER" ]; then
        if ! insmod "$MODULE" >> "$STATE/events.log" 2>&1; then
            log 'Module load failed; no interfaces will be detached. See dmesg.'
            exit 1
        fi
    fi
    [ -d "$DRIVERS/$DRIVER" ] || { log 'USB driver did not register.'; exit 1; }
    while [ ! -e "$DISABLED" ]; do
        [ -d "$DRIVERS/$DRIVER" ] || { log 'Driver disappeared; stopping.'; break; }
        scan
        sleep "$POLL"
    done
}

start_worker() {
    [ ! -e "$DISABLED" ] || { printf 'Disabled by %s\n' "$DISABLED"; return 0; }
    preflight
    init_state
    if is_running; then
        printf 'Already running, PID %s.\n' "$worker_pid"
        return 0
    fi
    [ -r "$SELF" ] || die "Install this script as $SELF first."
    nohup /bin/sh "$SELF" run </dev/null > "$STATE/startup.log" 2>&1 &
    printf 'Worker launch requested. Check: sh %s status\n' "$SELF"
}

stop_worker() {
    if is_running; then
        kill -TERM "$worker_pid" || return 1
        printf 'Stop requested for PID %s; an in-flight takeover may finish. No module unload or forced detach.\n' "$worker_pid"
    else
        printf 'No running worker found.\n'
    fi
}

install_hook() {
    preflight
    [ -r /var/lib/webosbrew/startup.sh ] || [ -f /tmp/webosbrew_startup ] ||
        die 'Homebrew startup hook not confirmed. Do not invent another init path; inspect the root startup setup first.'
    [ -f "$SELF" ] || die "First upload this file to $SELF"
    chmod 755 "$SELF" || exit 1
    mkdir -p /var/lib/webosbrew/init.d || exit 1
    if [ -e "$HOOK" ] || [ -L "$HOOK" ]; then
        [ "$(readlink "$HOOK")" = "$SELF" ] || die "Existing unrelated hook: $HOOK"
    else
        ln -s "$SELF" "$HOOK" || exit 1
    fi
    printf 'Boot hook installed: %s -> %s\n' "$HOOK" "$SELF"
    printf 'Start now with: sh %s start\n' "$SELF"
}

show_status() {
    printf 'Kernel: %s (expected %s)\n' "$(uname -r)" "$KERNEL"
    if [ "$(readlink "$HOOK" 2>/dev/null)" = "$SELF" ]; then
        printf 'Boot hook: installed\n'
    else
        printf 'Boot hook: not installed\n'
    fi
    [ ! -e "$DISABLED" ] || printf 'DISABLED marker present: %s\n' "$DISABLED"
    if is_running; then printf 'Worker: PID %s\n' "$worker_pid"; else printf 'Worker: stopped\n'; fi
    for net in /sys/class/net/*; do
        [ "$(driver_of "$net/device")" = "$DRIVER" ] || continue
        printf '%s: %s, carrier=%s, speed=%s Mbit/s, sg=%s\n' "${net##*/}" "$DRIVER" \
            "$(value "$net/carrier" 2>/dev/null)" "$(value "$net/speed" 2>/dev/null)" \
            "$(value "$net/rtl_adv/sg_en" 2>/dev/null || printf unavailable)"
    done
    printf '\nRecent worker events:\n'
    tail -n 15 "$STATE/events.log" 2>/dev/null || :
    printf '\nStartup messages:\n'
    tail -n 5 "$STATE/startup.log" 2>/dev/null || :
}

# Test harness can source functions without touching the real TV.
if [ "${R8152_AUTOBIND_SOURCE_ONLY:-0}" = 1 ]; then return 0; fi

case "${1:-start}" in
    start) start_worker ;;
    run) run_worker ;;
    stop) stop_worker ;;
    status) show_status ;;
    install) install_hook ;;
    disable)
        : > "$DISABLED" || exit 1
        stop_worker
        printf 'Disabled now and at boot. Remove %s to enable again.\n' "$DISABLED"
        ;;
    uninstall)
        if [ "$(readlink "$HOOK" 2>/dev/null)" = "$SELF" ]; then
            rm -f "$HOOK" || exit 1
            printf 'Removed only the r8152 boot-hook symlink.\n'
        elif [ -e "$HOOK" ] || [ -L "$HOOK" ]; then
            die "Refusing to remove unrelated $HOOK"
        fi
        stop_worker
        printf 'Script and module retained in /home/root. Reboot to return to normal driver selection.\n'
        ;;
    *) printf 'Usage: sh %s {start|stop|status|install|disable|uninstall}\n' "$SELF"; exit 2 ;;
esac
