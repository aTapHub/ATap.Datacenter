#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo 'prepare-kubernetes-host.sh must run as root.' >&2
    exit 1
fi

fstab_path='/etc/fstab'
fstab_backup_path='/etc/fstab.atap-before-kubernetes'
sysctl_path='/etc/sysctl.d/99-kubernetes.conf'
temporary_fstab="$(mktemp)"
temporary_sysctl="$(mktemp)"

cleanup() {
    rm -f "${temporary_fstab}" "${temporary_sysctl}"
}
trap cleanup EXIT

if [[ ! -e ${fstab_backup_path} ]]; then
    cp --archive "${fstab_path}" "${fstab_backup_path}"
fi

awk '
    /^[[:space:]]*#/ { print; next }
    $3 == "swap" { print "# Disabled for Kubernetes: " $0; next }
    { print }
' "${fstab_path}" > "${temporary_fstab}"

if ! cmp --silent "${temporary_fstab}" "${fstab_path}"; then
    install --owner=root --group=root --mode=0644 "${temporary_fstab}" "${fstab_path}"
fi

swapoff --all

printf '%s\n' \
    '# Required for Kubernetes node and Pod networking.' \
    'net.ipv4.ip_forward = 1' \
    > "${temporary_sysctl}"
install --owner=root --group=root --mode=0644 "${temporary_sysctl}" "${sysctl_path}"

sysctl --system >/dev/null

if swapon --show --noheadings | grep --quiet .; then
    echo 'Swap remains active after preparation.' >&2
    exit 1
fi

if awk '$3 == "swap" && $0 !~ /^[[:space:]]*#/ { found=1 } END { exit found ? 0 : 1 }' "${fstab_path}"; then
    echo 'An active swap entry remains in /etc/fstab.' >&2
    exit 1
fi

if [[ $(sysctl --values net.ipv4.ip_forward) != '1' ]]; then
    echo 'IPv4 forwarding is not enabled.' >&2
    exit 1
fi

echo 'Kubernetes base host preparation passed.'
