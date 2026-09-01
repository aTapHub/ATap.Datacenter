#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo 'initialize-control-plane.sh must run as root.' >&2
    exit 1
fi

if [[ $# -ne 2 ]]; then
    echo 'Usage: initialize-control-plane.sh <config-path> <operator-username>' >&2
    exit 1
fi

source_config_path=$1
operator_username=$2
installed_config_path='/etc/kubernetes/atap-kubeadm-init.yaml'
initialization_log_path='/var/log/atap-kubeadm-init.log'

if [[ ! -f ${source_config_path} ]]; then
    echo "Kubeadm configuration not found: ${source_config_path}" >&2
    exit 1
fi

if [[ -s /etc/kubernetes/admin.conf ]]; then
    echo 'The control plane is already initialized; refusing to run kubeadm init again.' >&2
    exit 1
fi

if ! id "${operator_username}" >/dev/null 2>&1; then
    echo "Operator account not found: ${operator_username}" >&2
    exit 1
fi

install --owner=root --group=root --mode=0644 \
    "${source_config_path}" \
    "${installed_config_path}"

umask 077
if ! kubeadm init --config "${installed_config_path}" > "${initialization_log_path}" 2>&1; then
    echo "kubeadm init failed; root-only diagnostics retained at ${initialization_log_path}." >&2
    exit 1
fi

operator_home=$(getent passwd "${operator_username}" | cut -d: -f6)
install --directory --owner="${operator_username}" --group="${operator_username}" --mode=0700 \
    "${operator_home}/.kube"
install --owner="${operator_username}" --group="${operator_username}" --mode=0600 \
    /etc/kubernetes/admin.conf \
    "${operator_home}/.kube/config"

rm -f "${initialization_log_path}"

systemctl is-active --quiet kubelet
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get --raw='/readyz' >/dev/null
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get node k8s-cp-01 >/dev/null

node_ready_status=$(
    KUBECONFIG=/etc/kubernetes/admin.conf kubectl get node k8s-cp-01 \
        --output=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
)
if [[ ${node_ready_status} != 'False' ]]; then
    echo "Expected k8s-cp-01 to be NotReady before CNI installation, got: ${node_ready_status}" >&2
    exit 1
fi

echo 'Control plane initialized; node is correctly NotReady until Calico is installed.'
