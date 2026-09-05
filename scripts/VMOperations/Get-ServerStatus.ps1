#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$vmNames = @('k8s-cp-01', 'k8s-worker-01', 'k8s-worker-02')

$status = foreach ($vmName in $vmNames) {
    $vm = Get-VM -Name $vmName -ErrorAction Stop
    $checkpointCount = @(Get-VMSnapshot -VM $vm -ErrorAction Stop).Count

    [pscustomobject]@{
        Name        = $vm.Name
        State       = $vm.State
        Uptime      = $vm.Uptime
        CPU         = $vm.CPUUsage
        MemoryGiB   = [math]::Round($vm.MemoryAssigned / 1GB, 2)
        Checkpoints = $checkpointCount
        Status      = $vm.Status
    }
}

$status | Format-Table -AutoSize
