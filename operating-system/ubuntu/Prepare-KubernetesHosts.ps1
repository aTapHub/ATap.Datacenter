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

$guestScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts\prepare-kubernetes-host.sh'

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

if (-not (Test-Path -LiteralPath $PrivateKeyPath -PathType Leaf)) {
    throw "Operator private key not found: $PrivateKeyPath"
}

if (-not (Test-Path -LiteralPath $guestScriptPath -PathType Leaf)) {
    throw "Guest preparation script not found: $guestScriptPath"
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
    $destination = "$OperatorUsername@$address`:/tmp/atap-prepare-kubernetes-host.sh"

    Invoke-ExternalCommand -Command 'scp' -Arguments (
        $sshOptions + @($guestScriptPath, $destination)
    )

    $prepareCommand = @(
        'sudo -n install -o root -g root -m 0755'
        '/tmp/atap-prepare-kubernetes-host.sh'
        '/usr/local/sbin/atap-prepare-kubernetes-host'
        '&& rm -f /tmp/atap-prepare-kubernetes-host.sh'
        '&& sudo -n /usr/local/sbin/atap-prepare-kubernetes-host'
    ) -join ' '

    Invoke-ExternalCommand -Command 'ssh' -Arguments (
        $sshOptions + @("$OperatorUsername@$address", $prepareCommand)
    )

    $validateCommand = @(
        'test -z "$(swapon --show --noheadings)"'
        '&& test "$(sysctl --values net.ipv4.ip_forward)" = "1"'
        '&& test -f /etc/fstab.atap-before-kubernetes'
        '&& test -f /etc/sysctl.d/99-kubernetes.conf'
    ) -join ' '

    Invoke-ExternalCommand -Command 'ssh' -Arguments (
        $sshOptions + @("$OperatorUsername@$address", $validateCommand)
    )

    Write-Output "$nodeName passed Kubernetes base host preparation."
}
