#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo 'Usage: install-calico.sh <version> <crds-sha256> <operator-sha256> <installation-path>' >&2
    exit 1
fi

calico_version=$1
expected_crds_sha256=$2
expected_operator_sha256=$3
installation_path=$4
temporary_directory=$(mktemp -d)
crds_path="${temporary_directory}/v1_crd_projectcalico_org.yaml"
operator_path="${temporary_directory}/tigera-operator.yaml"

cleanup() {
    rm -rf "${temporary_directory}"
}
trap cleanup EXIT

if [[ ! ${calico_version} =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid Calico version: ${calico_version}" >&2
    exit 1
fi

if [[ ! ${expected_crds_sha256} =~ ^[a-f0-9]{64}$ ]] ||
    [[ ! ${expected_operator_sha256} =~ ^[a-f0-9]{64}$ ]]; then
    echo 'Invalid Calico manifest checksum.' >&2
    exit 1
fi

if [[ ! -f ${installation_path} ]]; then
    echo "Calico Installation resource not found: ${installation_path}" >&2
    exit 1
fi

manifest_base_url="https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests"
curl --fail --silent --show-error --location \
    "${manifest_base_url}/v1_crd_projectcalico_org.yaml" \
    --output "${crds_path}"
curl --fail --silent --show-error --location \
    "${manifest_base_url}/tigera-operator.yaml" \
    --output "${operator_path}"

echo "${expected_crds_sha256}  ${crds_path}" | sha256sum --check --status
echo "${expected_operator_sha256}  ${operator_path}" | sha256sum --check --status

kubectl apply --server-side --force-conflicts --filename "${crds_path}"
kubectl apply --server-side --force-conflicts --filename "${operator_path}"
kubectl rollout status deployment/tigera-operator \
    --namespace=tigera-operator \
    --timeout=180s
kubectl apply --filename "${installation_path}"

kubectl wait tigerastatus/calico \
    --for=create \
    --timeout=120s
kubectl wait tigerastatus/calico \
    --for=condition=Available=True \
    --timeout=300s
for status_name in apiserver tiers; do
    kubectl wait "tigerastatus/${status_name}" \
        --for=create \
        --timeout=120s
    kubectl wait "tigerastatus/${status_name}" \
        --for=condition=Available=True \
        --timeout=300s
done
kubectl wait node/k8s-cp-01 \
    --for=condition=Ready=True \
    --timeout=180s
kubectl rollout status deployment/coredns \
    --namespace=kube-system \
    --timeout=180s

test "$(kubectl get installation.operator.tigera.io/default --output=jsonpath='{.spec.calicoNetwork.ipPools[0].cidr}')" = '10.244.0.0/16'
test "$(kubectl get installation.operator.tigera.io/default --output=jsonpath='{.spec.calicoNetwork.ipPools[0].encapsulation}')" = 'VXLAN'
test "$(kubectl get installation.operator.tigera.io/default --output=jsonpath='{.spec.calicoNetwork.bgp}')" = 'Disabled'

echo 'Calico installation and validation passed.'
