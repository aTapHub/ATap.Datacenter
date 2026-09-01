#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo 'install-containerd.sh must run as root.' >&2
    exit 1
fi

if [[ $# -ne 3 ]]; then
    echo 'Usage: install-containerd.sh <containerd-version> <runc-version> <config-path>' >&2
    exit 1
fi

containerd_version=$1
runc_version=$2
source_config_path=$3
containerd_config_dir='/etc/containerd'
containerd_config_path="${containerd_config_dir}/config.toml"
containerd_config_backup_path="${containerd_config_path}.atap-before-kubernetes"
modules_path='/etc/modules-load.d/containerd.conf'

if [[ ! -f ${source_config_path} ]]; then
    echo "Containerd configuration not found: ${source_config_path}" >&2
    exit 1
fi

if dpkg-query --show --showformat='${Status}\n' containerd.io 2>/dev/null | grep --quiet 'install ok installed'; then
    echo 'The containerd.io package is installed; refusing to mix package sources.' >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install --yes --no-install-recommends \
    "containerd=${containerd_version}" \
    "runc=${runc_version}"

printf '%s\n' \
    '# Required by the containerd overlayfs snapshotter.' \
    'overlay' \
    > "${modules_path}"
modprobe overlay

install --directory --owner=root --group=root --mode=0755 "${containerd_config_dir}"
if [[ -f ${containerd_config_path} && ! -e ${containerd_config_backup_path} ]]; then
    cp --archive "${containerd_config_path}" "${containerd_config_backup_path}"
fi
install --owner=root --group=root --mode=0644 "${source_config_path}" "${containerd_config_path}"

systemctl enable containerd >/dev/null
systemctl restart containerd

installed_containerd_version=$(dpkg-query --show --showformat='${Version}' containerd)
installed_runc_version=$(dpkg-query --show --showformat='${Version}' runc)

if [[ ${installed_containerd_version} != "${containerd_version}" ]]; then
    echo "Unexpected containerd version: ${installed_containerd_version}" >&2
    exit 1
fi

if [[ ${installed_runc_version} != "${runc_version}" ]]; then
    echo "Unexpected runc version: ${installed_runc_version}" >&2
    exit 1
fi

systemctl is-enabled --quiet containerd
systemctl is-active --quiet containerd
test -S /run/containerd/containerd.sock
grep --quiet '^overlay$' "${modules_path}"
grep --quiet '^overlay ' /proc/modules
grep --quiet 'SystemdCgroup = true' "${containerd_config_path}"

if ! ctr plugins list | awk '$1 == "io.containerd.cri.v1" && $2 == "runtime" && $NF == "ok" { found=1 } END { exit found ? 0 : 1 }'; then
    echo 'The containerd CRI runtime plugin is not healthy.' >&2
    exit 1
fi

echo 'Containerd installation and validation passed.'
