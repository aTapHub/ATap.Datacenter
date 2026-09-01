# Ubuntu guest configuration

This directory owns repeatable configuration applied after Terraform creates
the Ubuntu VMs. Image construction remains separate under `packer/`.

## Kubernetes base host preparation

The first host-preparation step makes the minimum operating-system changes
required before installing Kubernetes components:

* disables active swap and comments its persistent `/etc/fstab` entry;
* enables persistent IPv4 forwarding;
* retains `/swap.img` and a one-time `/etc/fstab` backup for rollback.

It intentionally does not install containerd, kubelet, kubeadm, or a CNI. Kernel
modules and additional network settings will be introduced with the component
that requires them.

From an elevated PowerShell session on the Hyper-V host, first load the operator
key into `ssh-agent`, then prepare one node:

```powershell
ssh-add 'D:\Homelab\keys\homelab-admin'
.\operating-system\ubuntu\Prepare-KubernetesHosts.ps1 -Node k8s-cp-01
```

The `-Node` parameter accepts one or more of these explicit names:

```text
k8s-cp-01
k8s-worker-01
k8s-worker-02
```

The wrapper copies the guest script to the selected node, installs it as
`/usr/local/sbin/atap-prepare-kubernetes-host`, runs it with passwordless
`sudo`, and validates the resulting state. Re-running it is safe.

## Validation

After rebooting a prepared node, verify:

```bash
swapon --show
sysctl --values net.ipv4.ip_forward
```

The first command should produce no entries, and the second should print `1`.

## Rollback

The original fstab is saved once as `/etc/fstab.atap-before-kubernetes`, and
the swap file is not deleted. If this preparation must be intentionally
reversed, restore that backup, remove `/etc/sysctl.d/99-kubernetes.conf`, reload
the sysctl configuration, and enable configured swap again. Rollback is an
operator action because Kubernetes nodes are expected to retain this state.

## Container runtime

Containerd is installed as a separate lifecycle step after base host
preparation. The repository currently pins the Ubuntu Noble packages validated
for this cluster:

* containerd `2.2.1-0ubuntu1~24.04.3`;
* runc `1.3.4-0ubuntu1~24.04.1`.

The configuration enables the containerd CRI runtime, selects `runc`, and uses
the systemd cgroup driver required by these cgroup v2 hosts. The `overlay`
kernel module is loaded persistently because containerd uses the overlayfs
snapshotter. CNI-specific networking remains a later step.

Install and validate one node at a time:

```powershell
.\operating-system\ubuntu\Install-ContainerRuntime.ps1 -Node k8s-cp-01
```

The wrapper installs the versioned packages, deploys the source-controlled
`config/containerd/config.toml`, enables the service, and verifies the socket,
kernel module, package versions, and CRI runtime plugin. Re-running it is safe.

After a reboot, the essential checks are:

```bash
systemctl is-enabled containerd
systemctl is-active containerd
sudo ctr plugins list
```

Package version changes must be intentional: update the wrapper defaults,
apply to one node, reboot and validate it, then roll the change through the
remaining nodes. If a pre-existing containerd configuration is replaced, its
one-time backup is retained as
`/etc/containerd/config.toml.atap-before-kubernetes`.

## Kubernetes packages

The cluster is pinned to Kubernetes `v1.36.4`. The kubelet, kubeadm, and kubectl
APT package version is `1.36.4-1.1` from the official per-minor `v1.36`
repository at `pkgs.k8s.io`. The supporting `cri-tools` and `kubernetes-cni`
packages are pinned to `1.36.0-1.1` and `1.9.1-1.1` respectively.

Install one node at a time:

```powershell
.\operating-system\ubuntu\Install-KubernetesPackages.ps1 -Node k8s-cp-01
```

The wrapper verifies the repository signing-key fingerprint, installs exact
package versions, places all five packages on APT hold, enables kubelet, and
validates the installed tools. Kubelet does not become healthy
until the node is initialized or joined with kubeadm; restart attempts before
that point are expected.

Kubernetes package upgrades require an explicit change to the wrapper's minor
repository and package-version defaults. Upgrade one node at a time using the
kubeadm upgrade procedure rather than removing the package holds globally.
