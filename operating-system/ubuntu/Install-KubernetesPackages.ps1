[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('k8s-cp-01', 'k8s-worker-01', 'k8s-worker-02')]
    [string[]] $Node,
    [ValidatePattern('^v1\.\d+$')]
    [string] $KubernetesMinorVersion = 'v1.36',
    [ValidatePattern('^\d+\.\d+\.\d+-\d+\.\d+$')]
    [string] $KubernetesPackageVersion = '1.36.4-1.1',
    [ValidatePattern('^\d+\.\d+\.\d+-\d+\.\d+$')]
    [string] $CriToolsPackageVersion = '1.36.0-1.1',
    [ValidatePattern('^\d+\.\d+\.\d+-\d+\.\d+$')]
    [string] $KubernetesCniPackageVersion = '1.9.1-1.1',
    [ValidatePattern('^[A-F0-9]{40}$')]
    [string] $RepositoryKeyFingerprint = 'DE15B14486CD377B9E876E1A234654DA9A296436',
    [string] $OperatorUsername = 'ubuntu',
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin'
)

$ErrorActionPreference = 'Stop'

$nodeAddresses = @{
    'k8s-cp-01' = '192.168.0.128'
    'k8s-worker-01' = '192.168.0.129'
    'k8s-worker-02' = '192.168.0.130'
}

$guestScriptPath = Join-Path $PSScriptRoot 'scripts\install-kubernetes-packages.sh'

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
        $sshOptions + @($guestScriptPath, "${remote}:/tmp/atap-install-kubernetes-packages.sh")
    )

    $installCommand = @(
        'sudo -n install -o root -g root -m 0755'
        '/tmp/atap-install-kubernetes-packages.sh'
        '/usr/local/sbin/atap-install-kubernetes-packages'
        "&& sudo -n /usr/local/sbin/atap-install-kubernetes-packages '$KubernetesMinorVersion' '$KubernetesPackageVersion' '$CriToolsPackageVersion' '$KubernetesCniPackageVersion' '$RepositoryKeyFingerprint'"
        '&& rm -f /tmp/atap-install-kubernetes-packages.sh'
    ) -join ' '

    Invoke-ExternalCommand -Command 'ssh' -Arguments (
        $sshOptions + @($remote, $installCommand)
    )

    Write-Output "$nodeName passed Kubernetes package installation and validation."
}
