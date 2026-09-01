[CmdletBinding()]
param(
    [string] $OperatorUsername = 'ubuntu',
    [string] $ControlPlaneAddress = '192.168.0.128',
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin'
)

$ErrorActionPreference = 'Stop'

$configurationPath = Join-Path $PSScriptRoot 'kubeadm-init.yaml'

function Assert-Command {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not installed or is not available on PATH."
    }
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory)]
        [string] $Command,
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

Assert-Command -Name 'ssh'
Assert-Command -Name 'scp'
Assert-Command -Name 'ssh-add'

foreach ($requiredPath in @($PrivateKeyPath, $configurationPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file not found: $requiredPath"
    }
}

& ssh-add -l | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'The SSH agent has no usable identity. Load the operator key with ssh-add first.'
}

$sshOptions = @(
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=10',
    '-o', 'IdentitiesOnly=yes',
    '-i', $PrivateKeyPath
)
$remote = "$OperatorUsername@$ControlPlaneAddress"
$remoteConfigurationPath = '/tmp/atap-kubeadm-init.yaml'
$remoteDryRunPath = '/tmp/atap-kubeadm-preflight-dryrun'

Invoke-ExternalCommand -Command 'scp' -Arguments (
    $sshOptions + @($configurationPath, "${remote}:$remoteConfigurationPath")
)

$preflightCommand = @(
    "sudo -n kubeadm config validate --config $remoteConfigurationPath"
    "&& sudo -n env KUBEADM_INIT_DRYRUN_DIR=$remoteDryRunPath kubeadm init phase preflight --dry-run --config $remoteConfigurationPath"
    "&& { if sudo -n test -e $remoteDryRunPath; then sudo -n find $remoteDryRunPath -depth -delete; fi; }"
    "&& rm -f $remoteConfigurationPath"
) -join ' '

Invoke-ExternalCommand -Command 'ssh' -Arguments (
    $sshOptions + @($remote, $preflightCommand)
)

Write-Output 'k8s-cp-01 passed kubeadm configuration validation and dry-run preflight.'
