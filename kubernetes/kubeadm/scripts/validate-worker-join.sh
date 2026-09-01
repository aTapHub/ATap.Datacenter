#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo 'Usage: validate-worker-join.sh <worker-name>' >&2
    exit 1
fi

worker_name=$1
validation_namespace='atap-network-validation'

case ${worker_name} in
    k8s-worker-01|k8s-worker-02) ;;
    *)
        echo "Unsupported worker name: ${worker_name}" >&2
        exit 1
        ;;
esac

cleanup() {
    kubectl delete namespace "${validation_namespace}" \
        --ignore-not-found \
        --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl wait "node/${worker_name}" \
    --for=condition=Ready=True \
    --timeout=240s

worker_pod_cidr=$(
    kubectl get "node/${worker_name}" --output=jsonpath='{.spec.podCIDR}'
)
if [[ -z ${worker_pod_cidr} ]] || [[ ${worker_pod_cidr} != 10.244.* ]]; then
    echo "Unexpected Pod CIDR for ${worker_name}: ${worker_pod_cidr}" >&2
    exit 1
fi

kubectl wait pod \
    --namespace=kube-system \
    --selector=k8s-app=kube-proxy \
    --field-selector="spec.nodeName=${worker_name}" \
    --for=condition=Ready=True \
    --timeout=180s
kubectl wait pod \
    --namespace=calico-system \
    --selector=k8s-app=calico-node \
    --field-selector="spec.nodeName=${worker_name}" \
    --for=condition=Ready=True \
    --timeout=240s

cleanup
kubectl create namespace "${validation_namespace}" >/dev/null

kubectl run network-server \
    --namespace="${validation_namespace}" \
    --image=busybox:1.37.0 \
    --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"${worker_name}\"}}" \
    --command -- sh -c \
    'mkdir -p /www; echo cross-node-ok > /www/index.html; httpd -f -p 8080 -h /www' >/dev/null
kubectl run network-client \
    --namespace="${validation_namespace}" \
    --image=busybox:1.37.0 \
    --restart=Never \
    --overrides='{"spec":{"nodeName":"k8s-cp-01"}}' \
    --command -- sleep 600 >/dev/null

kubectl wait pod/network-server \
    --namespace="${validation_namespace}" \
    --for=condition=Ready=True \
    --timeout=180s
kubectl wait pod/network-client \
    --namespace="${validation_namespace}" \
    --for=condition=Ready=True \
    --timeout=180s

server_ip=$(
    kubectl get pod/network-server \
        --namespace="${validation_namespace}" \
        --output=jsonpath='{.status.podIP}'
)
test -n "${server_ip}"

network_result=$(
    kubectl exec pod/network-client \
        --namespace="${validation_namespace}" \
        -- wget -qO- -T 10 "http://${server_ip}:8080"
)
test "${network_result}" = 'cross-node-ok'

kubectl exec pod/network-client \
    --namespace="${validation_namespace}" \
    -- nslookup kubernetes.default.svc.cluster.local >/dev/null

echo "${worker_name} is Ready; kube-proxy, Calico, cross-node networking, and DNS passed."
