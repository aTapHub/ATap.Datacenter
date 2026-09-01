[CmdletBinding()]
param(
    [string] $OperatorUsername = 'ubuntu',
    [string] $ControlPlaneAddress = '192.168.0.128',
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin'
)

$ErrorActionPreference = 'Stop'

$configurationPath = Join-Path $PSScriptRoot 'kubeadm-init.yaml'
$guestScriptPath = Join-Path $PSScriptRoot 'scripts\initialize-control-plane.sh'

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

foreach ($requiredPath in @($PrivateKeyPath, $configurationPath, $guestScriptPath)) {
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

& ssh @sshOptions $remote 'test ! -s /etc/kubernetes/admin.conf'
if ($LASTEXITCODE -ne 0) {
    throw 'The control plane is already initialized; refusing to copy files or run kubeadm init again.'
}

Invoke-ExternalCommand -Command 'scp' -Arguments (
    $sshOptions + @($configurationPath, "${remote}:/tmp/atap-kubeadm-init.yaml")
)
Invoke-ExternalCommand -Command 'scp' -Arguments (
    $sshOptions + @($guestScriptPath, "${remote}:/tmp/atap-initialize-control-plane.sh")
)

$initializeCommand = @(
    'sudo -n install -o root -g root -m 0755'
    '/tmp/atap-initialize-control-plane.sh'
    '/usr/local/sbin/atap-initialize-control-plane'
    "&& sudo -n /usr/local/sbin/atap-initialize-control-plane /tmp/atap-kubeadm-init.yaml '$OperatorUsername'"
    '&& rm -f /tmp/atap-kubeadm-init.yaml /tmp/atap-initialize-control-plane.sh'
) -join ' '

Invoke-ExternalCommand -Command 'ssh' -Arguments (
    $sshOptions + @($remote, $initializeCommand)
)

Write-Output 'k8s-cp-01 control plane initialized and validated.'
