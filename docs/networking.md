# Homelab network contract

The Kubernetes VMs use the existing Hyper-V external switch named
`Kubernetes`. Terraform reads this switch but does not create or destroy it.

## Address assignments

| Role | Hostname | Static MAC | Reserved IPv4 |
| --- | --- | --- | --- |
| Control plane | `k8s-cp-01` | `00155D00AD07` | `192.168.0.128` |
| Worker | `k8s-worker-01` | `00155D00AD08` | `192.168.0.129` |
| Worker | `k8s-worker-02` | `00155D00AD09` | `192.168.0.130` |

Network parameters discovered from the Hyper-V host:

* subnet: `192.168.0.0/24`;
* default gateway: `192.168.0.1`;
* DHCP server: `192.168.0.1`;
* DNS server: `192.168.0.1`.

Terraform pins each VM's MAC address. The TP-Link Archer C60 router owns DHCP
and reserves the listed IPv4 address for each MAC. Router configuration is
outside the current Terraform provider's ownership and is therefore a
documented host prerequisite.

Each reservation was verified by gracefully rebooting its VM independently.
All three guests returned on their assigned IPv4 addresses with SSH available.

The Archer C60 does not publish the reservations as local DNS records. The
Hyper-V host and Ubuntu guests therefore use the explicit mappings in this
document. Run the source-controlled configuration wrapper from an elevated
PowerShell session after loading the operator key into `ssh-agent`:

```powershell
.\operating-system\ubuntu\Configure-HostResolution.ps1
```

On Ubuntu, the wrapper installs the repository's cloud-init-compatible
`hosts.debian.tmpl`, regenerates `/etc/hosts`, and verifies every node mapping.
It also manages a clearly delimited block in the Windows hosts file.

The wrapper was verified as idempotent, and guest hostname resolution remained
correct after an independent reboot of `k8s-worker-02`.
