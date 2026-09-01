# Hyper-V Terraform stack

This stack deploys the control-plane VM and first worker VM from the immutable
base VHDX produced by Packer. The explicit `nodes` map is the first Terraform
generalization step; it avoids modules while the repeated VM relationships are
still being learned.

## Ownership boundary

Terraform manages:

* `k8s-cp-01` and `k8s-worker-01`;
* their writable OS-disk copies under `D:\Homelab\virtual-disks`;
* their small NoCloud seed ISOs under `D:\Homelab\cloud-init`.

Terraform reads, but does not manage or destroy:

* the `Kubernetes` Hyper-V switch;
* the versioned Packer base image under `D:\Homelab\images`.

Never attach the Packer VHDX directly to a VM. Each VM receives a standalone
copy so guest writes cannot modify the reusable image.

## One-time host input

Use an existing SSH key or create a separate human-operator key. Do not reuse
the temporary Packer build key:

```powershell
ssh-keygen -t ed25519 `
  -f 'D:\Homelab\keys\homelab-admin' `
  -C 'homelab-admin'
```

A passphrase is recommended for this human-operated private key. Terraform
reads only the `.pub` file.

Copy the example variables:

```powershell
Copy-Item '.\terraform.tfvars.example' '.\terraform.tfvars'
```

Confirm that `operator_ssh_public_key_path` and `ubuntu_base_image_path` match
files present on the Hyper-V host.

## Adding a node safely

Keep a newly declared node off during its first apply while existing nodes stay
running. For the first worker, run:

```powershell
terraform init -upgrade=false
terraform fmt -check
terraform validate
terraform plan `
  -var 'node_desired_states={worker_01="Off"}' `
  -out .\worker-01-off.tfplan
terraform apply .\worker-01-off.tfplan
```

Review the plan before applying it. It should create only the worker's copied
OS disk, seed ISO, and VM, leaving the worker off.

Hyper-V on Windows client enables automatic checkpoints on newly created VMs.
Provider 0.4.0 does not expose that VM setting, and an automatic checkpoint
changes the active disk from the Terraform-managed `.vhdx` to an `.avhdx`
differencing disk. Disable the setting while the VM is off, before its first
start:

```powershell
Set-VM -Name 'k8s-worker-01' -AutomaticCheckpointsEnabled $false

Get-VM -Name 'k8s-worker-01' |
  Select-Object Name, State, AutomaticCheckpointsEnabled
```

Confirm that the VM is `Off` and `AutomaticCheckpointsEnabled` is `False`.
This explicit host step is temporary until the provider can manage the setting
as source-controlled desired state.

Run a second plan and apply without the temporary override. The tracked default
is `Running`. This explicit two-stage operation is intentional: Hyper-V requires
the VM to be off while changing disk and DVD attachments.

```powershell
terraform plan -out .\worker-01-start.tfplan
terraform apply .\worker-01-start.tfplan
terraform output
```

Cloud-init reads the attached `CIDATA` ISO on first boot and creates the
configured hostname, operator account, SSH key, machine ID, and SSH host keys.
DHCP supplies the address on the existing external switch.

## Safe destruction and rebuilding

The provider deliberately uses a hard power-off when a running VM is destroyed.
For a clean lifecycle, temporarily override the tracked `Running` state, apply
the graceful stop, and pass the same override to destroy:

```powershell
terraform plan -var 'vm_desired_state=Off' -out .\stop-vm.tfplan
terraform apply .\stop-vm.tfplan
terraform destroy -var 'vm_desired_state=Off'
```

Destroy removes the disposable VM disk and seed ISO. It does not remove the
Packer base image or the host-owned virtual switch. A later `terraform apply`
copies the pristine base again and cloud-init establishes a fresh identity.

Treat changes to first-boot cloud-init data as image-instance lifecycle changes.
For this milestone, rebuild the disposable VM rather than attempting to mutate
an already initialized guest through its seed ISO. Repeated in-guest
configuration will later belong to configuration management.
