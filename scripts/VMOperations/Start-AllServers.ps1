#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

[CmdletBinding()]
param(
    [ValidateRange(30, 600)]
    [int] $TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

$controlPlaneName = 'k8s-cp-01'
$workerNames = @('k8s-worker-01', 'k8s-worker-02')
$vmNames = @($controlPlaneName) + $workerNames

function Get-RequiredVM {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Get-VM -Name $Name -ErrorAction Stop
}

function Start-RequiredVM {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $vm = Get-RequiredVM -Name $Name
    switch ([string] $vm.State) {
        'Running' { return }
        'Paused' {
            Resume-VM -VM $vm -ErrorAction Stop
            return
        }
        { $_ -in @('Off', 'Saved') } {
            Start-VM -VM $vm -ErrorAction Stop
            return
        }
        default {
            throw "Cannot start $Name while its state is $($vm.State)."
        }
    }
}

function Wait-ForRunningVM {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $vm = Get-RequiredVM -Name $Name
        if ([string] $vm.State -eq 'Running') {
            return
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "$Name did not reach Running within $TimeoutSeconds seconds."
}

foreach ($vmName in $vmNames) {
    [void] (Get-RequiredVM -Name $vmName)
}

Start-RequiredVM -Name $controlPlaneName
Wait-ForRunningVM -Name $controlPlaneName

foreach ($workerName in $workerNames) {
    Start-RequiredVM -Name $workerName
}
foreach ($workerName in $workerNames) {
    Wait-ForRunningVM -Name $workerName
}

Get-VM -Name $vmNames |
    Sort-Object Name |
    Select-Object Name, State, Status |
    Format-Table -AutoSize

Write-Output 'All homelab servers are running. Kubernetes may need a short time to become Ready.'
