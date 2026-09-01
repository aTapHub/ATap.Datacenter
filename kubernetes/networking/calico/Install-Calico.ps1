[CmdletBinding()]
param(
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string] $CalicoVersion = 'v3.32.1',
    [ValidatePattern('^[a-f0-9]{64}$')]
    [string] $CrdsSha256 = '192f8b2d934ef24b62e86b7e1a6e1762d1c8af26a916f78057bc13fa5ed60f71',
    [ValidatePattern('^[a-f0-9]{64}$')]
    [string] $OperatorSha256 = 'f18e073794207d372606bc3ea6f8fd73972f86d6828f4ba666dfe0d4aa8ab07f',
    [string] $OperatorUsername = 'ubuntu',
    [string] $ControlPlaneAddress = '192.168.0.128',
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin'
)

$ErrorActionPreference = 'Stop'

$installationPath = Join-Path $PSScriptRoot 'installation.yaml'
$guestScriptPath = Join-Path $PSScriptRoot 'scripts\install-calico.sh'

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

foreach ($requiredPath in @($PrivateKeyPath, $installationPath, $guestScriptPath)) {
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

Invoke-ExternalCommand -Command 'scp' -Arguments (
    $sshOptions + @($installationPath, "${remote}:/tmp/atap-calico-installation.yaml")
)
Invoke-ExternalCommand -Command 'scp' -Arguments (
    $sshOptions + @($guestScriptPath, "${remote}:/tmp/atap-install-calico.sh")
)

$installCommand = @(
    "bash /tmp/atap-install-calico.sh '$CalicoVersion' '$CrdsSha256' '$OperatorSha256' /tmp/atap-calico-installation.yaml"
    '&& rm -f /tmp/atap-calico-installation.yaml /tmp/atap-install-calico.sh'
) -join ' '

Invoke-ExternalCommand -Command 'ssh' -Arguments (
    $sshOptions + @($remote, $installCommand)
)

Write-Output 'Calico installation and control-plane network validation passed.'
