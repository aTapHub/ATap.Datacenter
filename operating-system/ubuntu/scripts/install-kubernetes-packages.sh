#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo 'install-kubernetes-packages.sh must run as root.' >&2
    exit 1
fi

if [[ $# -ne 5 ]]; then
    echo 'Usage: install-kubernetes-packages.sh <minor-version> <package-version> <cri-tools-version> <cni-version> <key-fingerprint>' >&2
    exit 1
fi

kubernetes_minor_version=$1
kubernetes_package_version=$2
cri_tools_package_version=$3
kubernetes_cni_package_version=$4
expected_key_fingerprint=$5
keyring_directory='/etc/apt/keyrings'
keyring_path="${keyring_directory}/kubernetes-apt-keyring.gpg"
keyring_backup_path="${keyring_path}.atap-before-kubernetes"
repository_path='/etc/apt/sources.list.d/kubernetes.list'
repository_backup_path='/etc/apt/kubernetes.list.atap-before-kubernetes'
legacy_repository_backup_path="${repository_path}.atap-before-kubernetes"
temporary_key=$(mktemp)
temporary_keyring=$(mktemp)
temporary_repository=$(mktemp)

cleanup() {
    rm -f "${temporary_key}" "${temporary_keyring}" "${temporary_repository}"
}
trap cleanup EXIT

if [[ ! ${kubernetes_minor_version} =~ ^v1\.[0-9]+$ ]]; then
    echo "Invalid Kubernetes minor version: ${kubernetes_minor_version}" >&2
    exit 1
fi

if [[ ! ${kubernetes_package_version} =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid Kubernetes package version: ${kubernetes_package_version}" >&2
    exit 1
fi

if [[ ! ${cri_tools_package_version} =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid cri-tools package version: ${cri_tools_package_version}" >&2
    exit 1
fi

if [[ ! ${kubernetes_cni_package_version} =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid kubernetes-cni package version: ${kubernetes_cni_package_version}" >&2
    exit 1
fi

if [[ ! ${expected_key_fingerprint} =~ ^[A-F0-9]{40}$ ]]; then
    echo 'Invalid repository key fingerprint.' >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

if [[ -f ${legacy_repository_backup_path} ]]; then
    if [[ ! -e ${repository_backup_path} ]]; then
        mv "${legacy_repository_backup_path}" "${repository_backup_path}"
    else
        rm -f "${legacy_repository_backup_path}"
    fi
fi

apt-get update -qq
apt-get install --yes --no-install-recommends ca-certificates curl gpg

repository_url="https://pkgs.k8s.io/core:/stable:/${kubernetes_minor_version}/deb/"
curl --fail --silent --show-error --location \
    "${repository_url}Release.key" \
    --output "${temporary_key}"

actual_key_fingerprint=$(
    gpg --show-keys --with-colons "${temporary_key}" 2>/dev/null |
        awk -F: '$1 == "fpr" { print $10; exit }'
)
if [[ ${actual_key_fingerprint} != "${expected_key_fingerprint}" ]]; then
    echo "Unexpected Kubernetes repository key fingerprint: ${actual_key_fingerprint}" >&2
    exit 1
fi

gpg --batch --yes --dearmor \
    --output "${temporary_keyring}" \
    "${temporary_key}"

install --directory --owner=root --group=root --mode=0755 "${keyring_directory}"
if [[ -f ${keyring_path} && ! -e ${keyring_backup_path} ]] &&
    ! cmp --silent "${temporary_keyring}" "${keyring_path}"; then
    cp --archive "${keyring_path}" "${keyring_backup_path}"
fi
install --owner=root --group=root --mode=0644 "${temporary_keyring}" "${keyring_path}"

printf 'deb [signed-by=%s] %s /\n' "${keyring_path}" "${repository_url}" \
    > "${temporary_repository}"
if [[ -f ${repository_path} && ! -e ${repository_backup_path} ]] &&
    ! cmp --silent "${temporary_repository}" "${repository_path}"; then
    cp --archive "${repository_path}" "${repository_backup_path}"
fi
install --owner=root --group=root --mode=0644 "${temporary_repository}" "${repository_path}"

apt-get update -qq

packages=(kubelet kubeadm kubectl)
for package_name in "${packages[@]}"; do
    if ! apt-cache madison "${package_name}" |
        awk '{ print $3 }' |
        grep --fixed-strings --line-regexp --quiet "${kubernetes_package_version}"; then
        echo "${package_name} ${kubernetes_package_version} is unavailable." >&2
        exit 1
    fi
done

if ! apt-cache madison cri-tools |
    awk '{ print $3 }' |
    grep --fixed-strings --line-regexp --quiet "${cri_tools_package_version}"; then
    echo "cri-tools ${cri_tools_package_version} is unavailable." >&2
    exit 1
fi

if ! apt-cache madison kubernetes-cni |
    awk '{ print $3 }' |
    grep --fixed-strings --line-regexp --quiet "${kubernetes_cni_package_version}"; then
    echo "kubernetes-cni ${kubernetes_cni_package_version} is unavailable." >&2
    exit 1
fi

apt-get install --yes --allow-change-held-packages \
    "kubelet=${kubernetes_package_version}" \
    "kubeadm=${kubernetes_package_version}" \
    "kubectl=${kubernetes_package_version}" \
    "cri-tools=${cri_tools_package_version}" \
    "kubernetes-cni=${kubernetes_cni_package_version}"
held_packages=("${packages[@]}" cri-tools kubernetes-cni)
apt-mark hold "${held_packages[@]}" >/dev/null
systemctl enable kubelet >/dev/null

for package_name in "${packages[@]}"; do
    installed_version=$(dpkg-query --show --showformat='${Version}' "${package_name}")
    if [[ ${installed_version} != "${kubernetes_package_version}" ]]; then
        echo "Unexpected ${package_name} version: ${installed_version}" >&2
        exit 1
    fi

    if ! apt-mark showhold | grep --fixed-strings --line-regexp --quiet "${package_name}"; then
        echo "${package_name} is not on hold." >&2
        exit 1
    fi
done

if [[ $(dpkg-query --show --showformat='${Version}' cri-tools) != "${cri_tools_package_version}" ]]; then
    echo 'Unexpected cri-tools version.' >&2
    exit 1
fi

if [[ $(dpkg-query --show --showformat='${Version}' kubernetes-cni) != "${kubernetes_cni_package_version}" ]]; then
    echo 'Unexpected kubernetes-cni version.' >&2
    exit 1
fi

for package_name in cri-tools kubernetes-cni; do
    if ! apt-mark showhold | grep --fixed-strings --line-regexp --quiet "${package_name}"; then
        echo "${package_name} is not on hold." >&2
        exit 1
    fi
done

systemctl is-enabled --quiet kubelet
systemctl is-active --quiet containerd
test -x /usr/bin/crictl
test -x /opt/cni/bin/loopback

echo 'Kubernetes package installation and validation passed.'
