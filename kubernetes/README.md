# Kubernetes cluster

The first cluster uses upstream Kubernetes `v1.36.4`, bootstrapped with
kubeadm. Infrastructure provisioning and Ubuntu configuration remain owned by
their respective repository layers.

## Current baseline

The initial cluster bootstrap is complete:

| Node | Role | Address | Pod CIDR |
| --- | --- | --- | --- |
| `k8s-cp-01` | Control plane | `192.168.0.128` | `10.244.0.0/24` |
| `k8s-worker-01` | Worker | `192.168.0.129` | `10.244.1.0/24` |
| `k8s-worker-02` | Worker | `192.168.0.130` | `10.244.2.0/24` |

Run the read-only operational baseline check from the Hyper-V host:

```powershell
.\kubernetes\Test-ClusterBaseline.ps1
```

It verifies API readiness, exact node identities and addresses, node readiness,
Pod CIDR allocation, Pod health, deployment and daemon-set availability, and
Calico operator status. Worker joining separately performs temporary
cross-node Pod and DNS tests because those checks intentionally create and then
remove test resources.

## Network contract

| Network | CIDR | Purpose |
| --- | --- | --- |
| Physical LAN | `192.168.0.0/24` | Hyper-V host and node addresses |
| Kubernetes Services | `10.96.0.0/12` | Cluster virtual service addresses |
| Kubernetes Pods | `10.244.0.0/16` | Pod addresses allocated by Calico |

These ranges do not overlap. The Pod CIDR is an input to both kubeadm and the
Calico installation and must remain consistent between them.

## Cluster networking

The initial CNI is Calico Open Source `v3.32.1`, installed with the Tigera
operator. VXLAN encapsulates cross-node Pod traffic, and BGP is disabled to keep
the first topology focused on Kubernetes networking rather than external route
distribution. Outbound Pod traffic is source-NATed by Calico.

The source-controlled Installation resource is under
`networking/calico/installation.yaml`. The installation wrapper pins and
verifies the upstream operator and CRD manifests before applying them.

## kubeadm configuration

The source-controlled control-plane configuration is
`kubeadm/kubeadm-init.yaml`. It binds the API server to `192.168.0.128`, uses
`k8s-cp-01:6443` as the stable control-plane endpoint, selects the containerd
CRI socket, and keeps the kubelet and containerd on the systemd cgroup driver.

Run configuration validation and the preflight phase without initializing the
cluster:

```powershell
.\kubernetes\kubeadm\Test-KubeadmPreflight.ps1
```

The wrapper invokes `kubeadm init phase preflight --dry-run`. It does not create
certificates, kubeconfig files, static Pod manifests, bootstrap tokens, or etcd
state.

After preflight succeeds, initialize the control plane explicitly:

```powershell
.\kubernetes\kubeadm\Initialize-ControlPlane.ps1
```

The wrapper refuses to run if `/etc/kubernetes/admin.conf` already exists. It
keeps kubeadm output, including bootstrap credentials, out of the terminal and
repository. On success it installs the admin kubeconfig for the `ubuntu`
operator and verifies that the API is healthy. The control-plane node remains
`NotReady` until Calico is installed; this is the expected boundary between
cluster bootstrap and Pod networking.

Install the pinned Calico operator and the source-controlled network resource:

```powershell
.\kubernetes\networking\calico\Install-Calico.ps1
```

The wrapper downloads the two official `v3.32.1` operator manifests, verifies
their pinned SHA-256 digests, and applies them using server-side apply. It then
applies `installation.yaml` and waits for Calico, the control-plane node, and
CoreDNS to become healthy. The same file enables the Calico API server required
for its tiered policy API. Re-running the wrapper reconciles the same declared
state.

## Worker join

Join one prepared worker at a time from the Hyper-V host:

```powershell
.\kubernetes\kubeadm\Join-Worker.ps1 -Worker k8s-worker-01
```

The wrapper verifies that the target is not already joined, creates a fresh
15-minute kubeadm bootstrap token on the control plane, and pipes the join
command directly to the worker. The token is held only in process memory and is
never printed, written to disk, or committed, and it is revoked immediately
after the join attempt. After the join, the wrapper waits for the node,
kube-proxy, and Calico to become healthy, then uses temporary pods to verify
cross-node Pod traffic and cluster DNS. The validation namespace is removed
automatically.

Joining changes cluster membership, so the wrapper intentionally refuses to
re-run against an existing node. Recovery or removal must use an explicit
kubeadm reset and Kubernetes node-removal procedure rather than this workflow.
