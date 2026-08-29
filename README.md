# ATap.Datacenter

ATap.Datacenter is a learning-oriented local datacenter and Kubernetes homelab. The project builds each infrastructure layer incrementally so that the underlying Terraform, Hyper-V, Linux, and Kubernetes concepts remain visible.

## Target architecture

The initial environment will run on a separate Windows desktop with Hyper-V and contain three Ubuntu Server virtual machines:

```text
Windows Hyper-V Host
        |
        +-- k8s-cp-01
        +-- k8s-worker-01
        +-- k8s-worker-02
```

The topology consists of one Kubernetes control-plane node and two worker nodes. Kubernetes will eventually be bootstrapped manually with `kubeadm`, but it is not part of the current milestone.

## Terraform execution

Terraform configuration can be edited from a development machine, but Terraform will run on the separate Windows Hyper-V host. Persistent VM images, configuration, and virtual disks will live under `D:\Homelab\` rather than on the host's `C:` drive.

## First milestone

The first infrastructure milestone is intentionally small: use Terraform to create and destroy one Hyper-V virtual machine successfully. The configuration will be generalized to all three machines only after that workflow is understood and verified.
