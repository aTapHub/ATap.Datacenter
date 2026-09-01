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
