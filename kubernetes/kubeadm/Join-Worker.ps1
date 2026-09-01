[CmdletBinding()]
param(
    [ValidateSet('k8s-worker-01', 'k8s-worker-02')]
    [string] $Worker = 'k8s-worker-01',
    [string] $OperatorUsername = 'ubuntu',
    [string] $ControlPlaneAddress = '192.168.0.128',
    [hashtable] $WorkerAddresses = @{
        'k8s-worker-01' = '192.168.0.129'
        'k8s-worker-02' = '192.168.0.130'
    },
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin'
)

$ErrorActionPreference = 'Stop'

$validationScriptPath = Join-Path $PSScriptRoot 'scripts\validate-worker-join.sh'

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

foreach ($requiredPath in @($PrivateKeyPath, $validationScriptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file not found: $requiredPath"
    }
}

if (-not $WorkerAddresses.ContainsKey($Worker)) {
    throw "No address is configured for worker: $Worker"
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
$controlPlaneRemote = "$OperatorUsername@$ControlPlaneAddress"
$workerRemote = "$OperatorUsername@$($WorkerAddresses[$Worker])"

Invoke-ExternalCommand -Command 'ssh' -Arguments (
    $sshOptions + @(
        $controlPlaneRemote,
        "kubectl get --raw=/readyz >/dev/null && ! kubectl get node '$Worker' >/dev/null 2>&1"
    )
)
Invoke-ExternalCommand -Command 'ssh' -Arguments (
    $sshOptions + @(
        $workerRemote,
        'test ! -s /etc/kubernetes/kubelet.conf && systemctl is-active --quiet containerd'
    )
)

Invoke-ExternalCommand -Command 'scp' -Arguments (
    $sshOptions + @($validationScriptPath, "${controlPlaneRemote}:/tmp/atap-validate-worker-join.sh")
)

$joinCommand = $null
$joinInput = $null
$tokenId = $null
try {
    $joinCommand = & ssh @sshOptions $controlPlaneRemote 'sudo -n kubeadm token create --ttl 15m --print-join-command' 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not generate a short-lived kubeadm join credential.'
    }

    $joinCommand = $joinCommand.Trim()

    $joinPattern = '^kubeadm join [A-Za-z0-9.-]+:[0-9]+ --token (?<tokenId>[a-z0-9]{6})\.[a-z0-9]{16} --discovery-token-ca-cert-hash sha256:[a-f0-9]{64}$'
    $joinMatch = [regex]::Match($joinCommand, $joinPattern)
    if (($joinCommand -isnot [string]) -or (-not $joinMatch.Success)) {
        throw 'The generated kubeadm join command did not match the expected safe format.'
    }
    $tokenId = $joinMatch.Groups['tokenId'].Value

    $joinInput = "$joinCommand --cri-socket unix:///run/containerd/containerd.sock`n"
    $joinInput | & ssh @sshOptions $workerRemote "tr -d '\r' | sudo -n bash -se"
    if ($LASTEXITCODE -ne 0) {
        throw "kubeadm join failed on $Worker."
    }
}
finally {
    if ($tokenId) {
        & ssh @sshOptions $controlPlaneRemote "sudo -n kubeadm token delete '$tokenId' >/dev/null" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'The short-lived kubeadm token could not be revoked immediately; it will expire after 15 minutes.'
        }
    }
    $tokenId = $null
    $joinInput = $null
    $joinCommand = $null
}

$validateCommand = @(
    'chmod 0700 /tmp/atap-validate-worker-join.sh'
    "&& /tmp/atap-validate-worker-join.sh '$Worker'"
    '&& rm -f /tmp/atap-validate-worker-join.sh'
) -join ' '

Invoke-ExternalCommand -Command 'ssh' -Arguments (
    $sshOptions + @($controlPlaneRemote, $validateCommand)
)

Write-Output "$Worker joined the cluster and passed network validation."
