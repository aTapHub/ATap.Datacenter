#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo 'prepare-calico-host.sh must run as root.' >&2
    exit 1
fi

modules_path='/etc/modules-load.d/calico.conf'

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install --yes --no-install-recommends conntrack ipset

printf '%s\n' \
    '# Required by the Calico VXLAN data plane.' \
    'vxlan' \
    > "${modules_path}"
modprobe vxlan

if systemctl is-active --quiet NetworkManager; then
    echo 'NetworkManager is active and may interfere with Calico interfaces.' >&2
    exit 1
fi

if systemctl is-active --quiet firewalld; then
    echo 'firewalld is active and may interfere with Calico rules.' >&2
    exit 1
fi

if command -v ufw >/dev/null && ufw status | grep --quiet '^Status: active$'; then
    echo 'UFW packet filtering is active and may interfere with Calico rules.' >&2
    exit 1
fi

dpkg --compare-versions "$(uname -r | cut -d- -f1)" ge '5.10'
command -v iptables >/dev/null
command -v ipset >/dev/null
command -v conntrack >/dev/null
grep --quiet '^vxlan$' "${modules_path}"
grep --quiet '^vxlan ' /proc/modules
test "$(sysctl --values net.ipv4.ip_forward)" = '1'
systemctl is-active --quiet containerd

echo 'Calico host preparation passed.'
