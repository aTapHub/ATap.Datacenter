# Homelab VM operations

These scripts provide quick, explicit power operations for the three
Kubernetes VMs. Run them from an elevated PowerShell session on the Hyper-V
host.

```powershell
D:\Homelab\VMOperations\Start-AllServers.ps1
D:\Homelab\VMOperations\Get-ServerStatus.ps1
D:\Homelab\VMOperations\Stop-AllServers.ps1
```

Startup brings up the control plane first, then both workers. Shutdown sends a
graceful guest shutdown to both workers, waits for them to stop, and only then
shuts down the control plane. It intentionally never uses Hyper-V's hard
`TurnOff` operation.

The status script is read-only and reports VM state, uptime, resource use, and
checkpoint count. After startup, use the repository's Kubernetes validation
when you need an end-to-end health check:

```powershell
C:\Repos\ATap.Datacenter\kubernetes\Test-ClusterBaseline.ps1
```

The source-controlled copies live in `scripts/VMOperations`. Deployed copies
under `D:\Homelab\VMOperations` are operational conveniences and should be
refreshed whenever their source changes.
