[CmdletBinding()]
param(
    [string] $OperatorUsername = 'ubuntu',
    [string] $ControlPlaneAddress = '192.168.0.128',
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin'
)

$ErrorActionPreference = 'Stop'

$expectedNodes = [ordered]@{
    'k8s-cp-01'     = @{
        Address = '192.168.0.128'
        PodCIDR = '10.244.0.0/24'
    }
    'k8s-worker-01' = @{
        Address = '192.168.0.129'
        PodCIDR = '10.244.1.0/24'
    }
    'k8s-worker-02' = @{
        Address = '192.168.0.130'
        PodCIDR = '10.244.2.0/24'
    }
}

foreach ($commandName in @('ssh', 'ssh-add')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "$commandName is not installed or is not available on PATH."
    }
}

if (-not (Test-Path -LiteralPath $PrivateKeyPath -PathType Leaf)) {
    throw "Private key not found: $PrivateKeyPath"
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

function Get-RemoteJson {
    param(
        [Parameter(Mandatory)]
        [string] $Command
    )

    $json = & ssh @sshOptions $remote $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Remote validation command failed: $Command"
    }

    return ($json | ConvertFrom-Json)
}

& ssh @sshOptions $remote 'kubectl get --raw=/readyz >/dev/null'
if ($LASTEXITCODE -ne 0) {
    throw 'The Kubernetes API readiness check failed.'
}

$nodes = (Get-RemoteJson -Command 'kubectl get nodes --output=json').items
if ($nodes.Count -ne $expectedNodes.Count) {
    throw "Expected $($expectedNodes.Count) nodes, found $($nodes.Count)."
}

foreach ($expectedNode in $expectedNodes.GetEnumerator()) {
    $node = $nodes | Where-Object { $_.metadata.name -eq $expectedNode.Key }
    if (-not $node) {
        throw "Expected node is missing: $($expectedNode.Key)"
    }

    $readyCondition = $node.status.conditions |
        Where-Object { $_.type -eq 'Ready' }
    if ($readyCondition.status -ne 'True') {
        throw "$($expectedNode.Key) is not Ready."
    }

    $internalAddress = $node.status.addresses |
        Where-Object { $_.type -eq 'InternalIP' }
    if ($internalAddress.address -ne $expectedNode.Value.Address) {
        throw "Unexpected address for $($expectedNode.Key): $($internalAddress.address)"
    }

    if ($node.spec.podCIDR -ne $expectedNode.Value.PodCIDR) {
        throw "Unexpected Pod CIDR for $($expectedNode.Key): $($node.spec.podCIDR)"
    }
}

$pods = (Get-RemoteJson -Command 'kubectl get pods --all-namespaces --output=json').items
$unhealthyPods = @(
    $pods | Where-Object {
        $_.status.phase -notin @('Running', 'Succeeded') -or
        ($_.status.phase -eq 'Running' -and
            @($_.status.containerStatuses | Where-Object { -not $_.ready }).Count -ne 0)
    }
)
if ($unhealthyPods.Count -ne 0) {
    $podNames = $unhealthyPods | ForEach-Object {
        "$($_.metadata.namespace)/$($_.metadata.name)"
    }
    throw "Unhealthy Pods: $($podNames -join ', ')"
}

$deployments = (Get-RemoteJson -Command 'kubectl get deployments --all-namespaces --output=json').items
$unavailableDeployments = @(
    $deployments | Where-Object {
        [int] $_.status.availableReplicas -ne [int] $_.spec.replicas
    }
)
if ($unavailableDeployments.Count -ne 0) {
    throw 'One or more Kubernetes deployments are unavailable.'
}

$daemonSets = (Get-RemoteJson -Command 'kubectl get daemonsets --all-namespaces --output=json').items
$unavailableDaemonSets = @(
    $daemonSets | Where-Object {
        [int] $_.status.numberReady -ne [int] $_.status.desiredNumberScheduled
    }
)
if ($unavailableDaemonSets.Count -ne 0) {
    throw 'One or more Kubernetes daemon sets are unavailable.'
}

$tigeraStatuses = (Get-RemoteJson -Command 'kubectl get tigerastatus --output=json').items
foreach ($status in $tigeraStatuses) {
    $available = $status.status.conditions |
        Where-Object { $_.type -eq 'Available' }
    $degraded = $status.status.conditions |
        Where-Object { $_.type -eq 'Degraded' }
    if ($available.status -ne 'True' -or $degraded.status -ne 'False') {
        throw "Calico component is unhealthy: $($status.metadata.name)"
    }
}

$nodes |
    Sort-Object { $_.metadata.name } |
    ForEach-Object {
        [pscustomobject]@{
            Name      = $_.metadata.name
            InternalIP = ($_.status.addresses | Where-Object type -EQ 'InternalIP').address
            PodCIDR   = $_.spec.podCIDR
            Ready     = 'True'
        }
    } |
    Format-Table -AutoSize

Write-Output 'Three-node Kubernetes cluster baseline validation passed.'
