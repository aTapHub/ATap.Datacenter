# ATap.Datacenter

ATap.Datacenter is a learning-oriented local datacenter and Kubernetes homelab. The project builds each infrastructure layer incrementally so that the underlying Terraform, Hyper-V, Linux, and Kubernetes concepts remain visible, while converging on repeatable enterprise-style lifecycle management.

## Target architecture

The initial environment will run on a separate Windows desktop with Hyper-V and contain three Ubuntu Server virtual machines:

```text
Windows Hyper-V Host
        |
        +-- k8s-cp-01
        +-- k8s-worker-01
        +-- k8s-worker-02
```

The topology consists of one Kubernetes control-plane node and two worker
nodes. The initial upstream Kubernetes cluster is bootstrapped with `kubeadm`
and uses Calico for Pod networking.

## Terraform execution

Terraform configuration can be edited from a development machine, but Terraform will run on the separate Windows Hyper-V host. Persistent VM images, configuration, and virtual disks will live under `D:\Homelab\` rather than on the host's `C:` drive.

## Learning and automation approach

Manual work may be used to expose an important mechanism, establish a known-good reference, or diagnose a failure. It should have an explicit reason and a planned automation successor; routine provisioning, configuration, validation, patching, recovery, and rebuilding should ultimately be repeatable and source controlled.

The reproducible-provisioning milestone is complete. Packer produces a generalized Ubuntu image, and Terraform now provisions one SSH-ready control-plane VM and two SSH-ready worker VMs without managing or destroying the stable Hyper-V host network. Each VM has its own writable disk and NoCloud identity media derived from immutable inputs.

The Kubernetes host-preparation and bootstrap milestone is also complete. All
three Ubuntu guests use pinned Kubernetes packages and containerd, the control
plane is initialized, both workers are joined, and Calico provides VXLAN Pod
networking. Operating-system configuration, cluster bootstrap, and Hyper-V
infrastructure remain separate lifecycle layers.

The next learning step is the Kubernetes workload layer: explicitly deploy a
small application, expose it with a Service, and observe scheduling,
self-healing, and scaling before introducing higher-level platform tooling.

## Ubuntu image pipeline

Packer and Ubuntu autoinstall build a reusable Hyper-V VHDX from the official Ubuntu Server ISO. Terraform copies that immutable base disk into a disposable per-VM VHDX and attaches a generated NoCloud seed ISO for first-boot identity; Terraform does not run the operating-system installer itself.

The image recipe is under [`operating-system/ubuntu/packer`](operating-system/ubuntu/packer). Builds run on the Windows Hyper-V host because they create a temporary Hyper-V VM. Generated images and temporary VM data remain under `D:\Homelab` and are not committed to Git.

The three-VM deployment and lifecycle instructions are under [`infrastructure/hyperv`](infrastructure/hyperv).
The stable address assignments and network ownership boundary are documented
in [`docs/networking.md`](docs/networking.md).

## Independent execution phases

Build a new immutable image only when the Ubuntu image recipe changes:

```powershell
.\operating-system\ubuntu\packer\Build-Image.ps1
```

For normal infrastructure changes or VM rebuilds, reuse the image configured by
`ubuntu_base_image_path` and run Terraform independently:

```powershell
.\infrastructure\hyperv\Deploy-VMs.ps1
```

Neither script invokes the other. This keeps image construction and VM
deployment as separate lifecycle operations.
