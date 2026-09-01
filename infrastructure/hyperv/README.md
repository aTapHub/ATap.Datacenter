# Hyper-V Terraform stack

This stack deploys one disposable Ubuntu control-plane VM from the immutable
base VHDX produced by Packer.

## Ownership boundary

Terraform manages:

* `k8s-cp-01`;
* its writable OS-disk copy under `D:\Homelab\virtual-disks`;
* its small NoCloud seed ISO under `D:\Homelab\cloud-init`.

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

## First migration from the learning-stage VM

The existing VM and blank/manual-install disk predate Terraform power-state
management. If `k8s-cp-01` currently exists and is running, shut it down once
through the guest or with Hyper-V's graceful integration-service request:

```powershell
Stop-VM -Name 'k8s-cp-01'
```

Do not use `-TurnOff`.

Override the repository's normal `Running` state for this one-time migration,
then run:

```powershell
terraform init -upgrade=false
terraform fmt -check
terraform validate
terraform plan -var 'vm_desired_state=Off' -out .\first-boot.tfplan
terraform apply .\first-boot.tfplan
```

Review the plan before applying it. It should create the copied OS disk and
seed ISO, update or create the VM, and leave the VM off. The older
`k8s-cp-01.vhdx` resource may be destroyed after Terraform detaches it.

Hyper-V on Windows client enables automatic checkpoints on newly created VMs.
Provider 0.4.0 does not expose that VM setting, and an automatic checkpoint
changes the active disk from the Terraform-managed `.vhdx` to an `.avhdx`
differencing disk. Disable the setting while the VM is off, before its first
start:

```powershell
Set-VM -Name 'k8s-cp-01' -AutomaticCheckpointsEnabled $false

Get-VM -Name 'k8s-cp-01' |
  Select-Object Name, State, AutomaticCheckpointsEnabled
```

Confirm that the VM is `Off` and `AutomaticCheckpointsEnabled` is `False`.
This explicit host step is temporary until the provider can manage the setting
as source-controlled desired state.

Run a second plan and apply without the temporary override. The tracked default
is `Running`. This explicit two-stage operation is intentional: Hyper-V requires
the VM to be off while changing disk and DVD attachments.

```powershell
terraform plan -out .\start-vm.tfplan
terraform apply .\start-vm.tfplan
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
