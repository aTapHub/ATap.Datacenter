# Ubuntu Hyper-V base image

This directory contains the source-controlled recipe for building a generalized Ubuntu Server 24.04 VHDX. The build runs on the Windows Hyper-V host, not on a development laptop.

## Build boundary

Packer owns the image-building lifecycle:

1. Create a temporary Generation 2 Hyper-V VM.
2. Attach the official Ubuntu ISO and a generated `cidata` ISO.
3. Boot Ubuntu autoinstall without interactive installer input.
4. Wait for SSH, validate the guest, and generalize its identity.
5. Shut down cleanly and retain the resulting VHDX.
6. Remove the temporary VM registration.

Terraform does not invoke Packer. A later Terraform change will copy the validated base VHDX into an independently managed per-VM disk.

## Host prerequisites

Install on the Windows Hyper-V host:

* HashiCorp Packer 1.16.0 on `PATH`.
* The Hyper-V PowerShell module and permission to create Hyper-V VMs.
* One ISO creation tool on `PATH`: `oscdimg`, `xorriso`, or `mkisofs`.
* Windows OpenSSH client tools, including `ssh-keygen`.

`oscdimg` is provided by the Deployment Tools component of the Windows Assessment and Deployment Kit (ADK). Packer uses it only to create the small NoCloud `cidata` ISO; it does not modify the Ubuntu installer ISO.

The template pins the HashiCorp Hyper-V Packer plugin to `1.1.5`.

## One-time preparation

Create a temporary build key outside the repository:

```powershell
New-Item -ItemType Directory -Path 'D:\Homelab\keys' -Force
ssh-keygen -t ed25519 -f 'D:\Homelab\keys\packer-build' -C 'packer-build'
```

Choose no passphrase for this automation-only key. Its private half remains on the Hyper-V host and is used only during image construction. The image-generalization step removes the public key from the completed image and disables the temporary build account.

Copy the example variables file:

```powershell
Copy-Item `
  '.\local.pkrvars.hcl.example' `
  '.\local.pkrvars.hcl'
```

Replace `REPLACE_WITH_THE_PUBLIC_KEY` with the contents of:

```text
D:\Homelab\keys\packer-build.pub
```

`local.pkrvars.hcl` and all `*.pkrvars.hcl` files are ignored by Git because they can contain host-specific or sensitive values.

## Verify the Ubuntu ISO

The template pins Ubuntu Server 24.04.4 to Canonical's published checksum:

```text
e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433
```

Verify the local file before building:

```powershell
Get-FileHash `
  'D:\Homelab\images\ubuntu-24.04.4-live-server-amd64.iso' `
  -Algorithm SHA256
```

Packer checks the same digest before it boots the installer.

## Build

From this directory on the Hyper-V host:

```powershell
.\Build-Image.ps1
```

The wrapper performs preflight checks, creates the required `D:\Homelab` directories, installs the pinned Packer plugin, checks formatting, validates the template, and starts the build.

The first build intentionally opens VMConnect. Do not interact with the installer; use the console only to see whether Packer reaches GRUB and starts autoinstall. Once the boot automation is proven, set this in `local.pkrvars.hcl`:

```hcl
headless = true
```

Successful output is stored under:

```text
D:\Homelab\images\ubuntu-24.04.4-base-v3\Virtual Hard Disks\
```

Use a new `image_version` for the next build instead of overwriting a base image already referenced by deployed VMs.

## Security and image identity

The build uses SSH public-key authentication and disables password authentication. No private key or plaintext password is embedded in the recipe.

Before shutdown, `prepare-image.sh`:

* removes the temporary account's authorized key;
* locks that account and assigns `nologin`;
* removes SSH host keys;
* removes Subiquity's installer-only datasource and disable marker;
* cleans cloud-init state and the machine ID;
* removes transient package and random-seed data.

The repository's `.gitattributes` keeps guest `.sh` files on LF line endings.
These scripts execute directly inside Linux, where a CRLF shebang would prevent
the kernel from locating `/usr/bin/env bash`.

Each VM deployed from the resulting VHDX must receive its own cloud-init NoCloud seed so that it generates a unique machine identity, SSH host keys, hostname, and operator account.
