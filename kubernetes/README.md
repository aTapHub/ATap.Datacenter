# Kubernetes cluster

The first cluster uses upstream Kubernetes `v1.36.4`, bootstrapped with
kubeadm. Infrastructure provisioning and Ubuntu configuration remain owned by
their respective repository layers.

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
`networking/calico/installation.yaml`. The pinned operator and CRD installation
process will be added after the control plane is initialized.

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
