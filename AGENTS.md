# ATap.Datacenter — AGENTS.md

## Project purpose

ATap.Datacenter is a learning-oriented local datacenter and Kubernetes homelab.

The goal is to build a small but realistic infrastructure environment from first principles while understanding every major layer involved.

The initial environment will run on a separate Windows desktop using Hyper-V.

The repository may be edited from other development machines, but infrastructure execution will happen on the Windows Hyper-V host.

---

## Physical host

Target Hyper-V host:

* Windows
* Hyper-V enabled
* AMD Ryzen 5 5600
* 6 physical cores / 12 threads
* 32 GB RAM
* VM storage must live on `D:\`
* `C:\` has limited free space and must not be used for large VM files

---

## Initial architecture

The first version of the datacenter will consist of:

* 3 Ubuntu Server virtual machines
* 1 Kubernetes control-plane node
* 2 Kubernetes worker nodes

Target topology:

```text
Windows Hyper-V Host
        |
        +-- k8s-cp-01
        |
        +-- k8s-worker-01
        |
        +-- k8s-worker-02
```

Kubernetes will initially be installed manually using kubeadm so that the underlying concepts are learned rather than hidden behind higher-level automation.

---

## Learning objectives

This project exists primarily for learning.

Important topics include:

* Terraform fundamentals
* Terraform state and desired-state infrastructure
* Terraform providers
* Hyper-V networking
* Virtual machines and virtual disks
* Linux administration
* Linux networking
* SSH
* systemd
* container runtimes
* Kubernetes architecture
* kubeadm
* kubelet
* kubectl
* Kubernetes control plane
* worker-node joining
* CNI networking
* DNS
* routing
* load balancing
* observability
* GitOps
* distributed testing
* chaos engineering

Later phases may introduce:

* Ansible
* Helm
* Argo CD
* Prometheus
* Grafana
* Loki
* OpenTelemetry
* MetalLB
* ingress controllers
* cert-manager
* distributed test execution
* k6
* Playwright
* C# test workloads
* chaos experiments

These should not be introduced prematurely.

---

## Enterprise learning direction

The learning environment should converge toward enterprise-style lifecycle management, not remain a collection of manual procedures.

For each infrastructure layer, learn both the underlying mechanism and how that layer is operated repeatably. The eventual lifecycle should cover:

* provisioning
* configuration
* validation
* patching and upgrades
* recovery
* safe destruction and rebuilding
* documentation and operational troubleshooting

Manual work is appropriate when it reveals an important mechanism for the first time, establishes a known-good reference, or is necessary for diagnosis. Before using a manual step, explain:

1. What concept the step is intended to teach or verify.
2. Why automation would hide that concept or is not yet justified.
3. Whether the step changes source-controlled desired state.
4. What automation or documented process will replace it later.

Do not repeat a manual process after its learning value has been exhausted when a repeatable implementation is the actual objective.

Enterprise focus does not mean introducing every enterprise tool immediately. Add tooling when its operational responsibility is understood and there is a concrete lifecycle problem for it to solve.

---

## Core engineering principles

### 1. Learn before abstracting

Prefer explicit infrastructure definitions while learning.

Do not introduce Terraform modules until repetition or complexity clearly justifies them.

Do not hide infrastructure concepts behind abstractions before they have been understood.

### 2. Small incremental changes

Each change should introduce as few new concepts as practical.

Preferred progression:

1. Terraform provider configuration
2. Terraform communicating with Hyper-V
3. Create one VM
4. Destroy and recreate one VM
5. Add networking
6. Generalize the VM definition
7. Create three VMs
8. Install/configure Ubuntu
9. Prepare Linux for Kubernetes
10. Bootstrap Kubernetes control plane
11. Join worker nodes
12. Install Kubernetes networking
13. Add platform services

Do not skip directly to a complete cluster.

### 3. Infrastructure as Code

Hyper-V infrastructure should be reproducible using Terraform.

Manual infrastructure configuration should be avoided unless the manual step is intentionally being performed for learning.

If a manual step is required, document why.

### 4. Separate infrastructure layers

Keep these concerns conceptually separate:

```text
Physical machine
    ↓
Hyper-V
    ↓
Virtual machine infrastructure
    ↓
Ubuntu
    ↓
Container runtime
    ↓
Kubernetes
    ↓
Platform services
    ↓
Applications and test workloads
```

Changes to one layer should not unnecessarily couple it to another.

### 5. Explain before implementing

For non-trivial infrastructure changes:

1. Inspect the existing repository.
2. Explain the proposed change.
3. Explain what new concept is being introduced.
4. Identify the files that will change.
5. Implement only after the approach is clear.

The goal is understanding, not maximum implementation speed.

---

## Terraform rules

Terraform will initially run directly on the Windows Hyper-V host.

Terraform configuration should be readable and explicit.

Prefer:

* clear resource names
* clear variables
* minimal indirection
* comments where the reason for something is not obvious
* `terraform fmt`
* `terraform validate`

Avoid:

* premature modules
* complex dynamic blocks
* unnecessary locals
* overly generic abstractions
* copy-pasted generated code that is not understood

Terraform state files must not be committed to Git.

Generated provider directories must not be committed.

Secrets must never be committed.

---

## Hyper-V rules

All persistent VM-related data must live under `D:\`.

Proposed location:

```text
D:\Homelab\
    images\
    virtual-machines\
    virtual-disks\
```

The exact path may evolve, but large VM artifacts must not be placed on `C:\`.

VM naming convention:

```text
k8s-cp-01
k8s-worker-01
k8s-worker-02
```

Initial VM sizing should remain conservative because the host has 32 GB RAM.

Approximate starting sizes:

Control plane:

* 2 vCPU
* 4 GB RAM
* 40 GB dynamically expanding disk

Worker nodes:

* 2 vCPU
* 6 GB RAM
* 50 GB dynamically expanding disk

These values may be changed later based on measured usage.

---

## Ubuntu

The initial guest operating system is Ubuntu Server LTS.

Ubuntu is being used intentionally to learn:

* Linux administration
* networking
* SSH
* package management
* systemd
* Kubernetes host preparation

Do not replace Ubuntu with Talos, MicroK8s, k3s, Docker Desktop Kubernetes, or another simplified Kubernetes distribution unless explicitly requested.

---

## Kubernetes

The first cluster will be built using upstream Kubernetes components and kubeadm.

Do not use:

* k3s
* MicroK8s
* minikube
* kind
* Docker Desktop Kubernetes

for the primary cluster.

The goal is to understand Kubernetes bootstrap and node configuration.

Initial topology:

```text
1 control-plane node
2 worker nodes
```

High availability is not a requirement for the first version.

---

## Automation progression

Automation should be introduced progressively, after the mechanism and ownership boundary are understood.

The expected progression is:

### Phase 1

Terraform manages Hyper-V resources.

### Phase 2

Build a repeatable Ubuntu provisioning process. A first manual installation may be used as a reference, but routine VM creation should become unattended and reproducible.

### Phase 3

Manage repeated Linux configuration, validation, patching, and Kubernetes host preparation with an appropriate configuration-management process, potentially Ansible.

### Phase 4

Bootstrap Kubernetes with upstream components and kubeadm. Perform the first bootstrap explicitly enough to understand it, then automate repeated cluster lifecycle operations where doing so preserves that understanding.

### Phase 5

Manage Kubernetes application and platform configuration declaratively, potentially moving toward GitOps using Argo CD.

This progression is intentional.

---

## Repository structure

Initial preferred structure:

```text
ATap.Datacenter/
|
+-- infrastructure/
|   +-- hyperv/
|
+-- operating-system/
|   +-- ubuntu/
|
+-- kubernetes/
|
+-- scripts/
|
+-- docs/
|
+-- .gitignore
+-- AGENTS.md
+-- README.md
```

The structure should remain simple while the project is small.

Do not create large nested directory hierarchies without a concrete need.

---

## Codex behavior

When working in this repository:

* Treat this as a teaching project.
* Do not optimize primarily for speed.
* Do not generate a complete datacenter or Kubernetes cluster in one operation.
* Introduce infrastructure incrementally.
* Explain unfamiliar Terraform, Hyper-V, Linux, and Kubernetes concepts.
* Prefer the smallest implementation that demonstrates the current concept.
* Avoid adding technologies that were not requested.
* Do not silently introduce architecture changes.
* Do not refactor working learning-oriented code merely to make it more sophisticated.
* Preserve readable intermediate stages even if a production system might abstract them further.

When asked to implement something:

1. Inspect existing files first.
2. State what you found.
3. Explain what you intend to change.
4. Make the smallest necessary change.
5. Run relevant validation where possible.
6. Explain the resulting behavior.

If infrastructure commands cannot be executed because Codex is running on a development laptop rather than the Hyper-V host, do not fake successful execution. Clearly state which commands must later be run on the Hyper-V host.

---

## Current milestone

We are currently at:

**Milestone 1 — Reproducible Ubuntu VM provisioning**

Milestone 0 proved that Terraform can create and destroy one Hyper-V VM and introduced its virtual disk, firmware, installation media, and networking relationships.

The immediate objective is now:

> Reproducibly provision one SSH-ready Ubuntu VM, then destroy and rebuild its disposable resources without destroying stable Hyper-V host networking.

The implementation should establish a clear boundary between stable host infrastructure and disposable VM infrastructure. It should replace repeated interactive Ubuntu installation with an unattended installation or reusable-image process whose inputs are stored in source control.

Only after this lifecycle is understood and verified should the VM definition be generalized to three machines.
