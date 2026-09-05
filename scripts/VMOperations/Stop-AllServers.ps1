#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

[CmdletBinding()]
param(
    [ValidateRange(30, 600)]
    [int] $TimeoutSeconds = 180
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

function Request-GracefulShutdown {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $vm = Get-RequiredVM -Name $Name
    if ([string] $vm.State -in @('Off', 'Saved')) {
        return
    }
    if ([string] $vm.State -eq 'Paused') {
        Resume-VM -VM $vm -ErrorAction Stop
        $vm = Get-RequiredVM -Name $Name
    }
    if ([string] $vm.State -ne 'Running') {
        throw "Cannot gracefully shut down $Name while its state is $($vm.State)."
    }

    $shutdownService = Get-VMIntegrationService -VMName $Name -Name 'Shutdown' -ErrorAction Stop
    if (-not $shutdownService.Enabled) {
        throw "The Hyper-V Shutdown integration service is disabled for $Name."
    }

    Stop-VM -VM $vm -ErrorAction Stop
}

function Wait-ForStoppedVM {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $vm = Get-RequiredVM -Name $Name
        if ([string] $vm.State -in @('Off', 'Saved')) {
            return
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "$Name did not shut down within $TimeoutSeconds seconds. No hard power-off was attempted."
}

foreach ($vmName in $vmNames) {
    [void] (Get-RequiredVM -Name $vmName)
}

foreach ($workerName in $workerNames) {
    Request-GracefulShutdown -Name $workerName
}
foreach ($workerName in $workerNames) {
    Wait-ForStoppedVM -Name $workerName
}

Request-GracefulShutdown -Name $controlPlaneName
Wait-ForStoppedVM -Name $controlPlaneName

Get-VM -Name $vmNames |
    Sort-Object Name |
    Select-Object Name, State, Status |
    Format-Table -AutoSize

Write-Output 'All homelab servers shut down gracefully.'
