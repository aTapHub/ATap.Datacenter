[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('k8s-cp-01', 'k8s-worker-01', 'k8s-worker-02')]
    [string[]] $Node,
    [string] $OperatorUsername = 'ubuntu',
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin'
)

$ErrorActionPreference = 'Stop'

$nodeAddresses = @{
    'k8s-cp-01' = '192.168.0.128'
    'k8s-worker-01' = '192.168.0.129'
    'k8s-worker-02' = '192.168.0.130'
}

$guestScriptPath = Join-Path $PSScriptRoot 'scripts\prepare-calico-host.sh'

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

foreach ($requiredPath in @($PrivateKeyPath, $guestScriptPath)) {
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

foreach ($nodeName in $Node) {
    $address = $nodeAddresses[$nodeName]
    $remote = "$OperatorUsername@$address"

    Invoke-ExternalCommand -Command 'scp' -Arguments (
        $sshOptions + @($guestScriptPath, "${remote}:/tmp/atap-prepare-calico-host.sh")
    )

    $prepareCommand = @(
        'sudo -n install -o root -g root -m 0755'
        '/tmp/atap-prepare-calico-host.sh'
        '/usr/local/sbin/atap-prepare-calico-host'
        '&& sudo -n /usr/local/sbin/atap-prepare-calico-host'
        '&& rm -f /tmp/atap-prepare-calico-host.sh'
    ) -join ' '

    Invoke-ExternalCommand -Command 'ssh' -Arguments (
        $sshOptions + @($remote, $prepareCommand)
    )

    Write-Output "$nodeName passed Calico host preparation."
}
