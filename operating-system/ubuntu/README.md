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
