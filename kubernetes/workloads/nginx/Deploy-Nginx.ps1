[CmdletBinding()]
param(
    [string] $OperatorUsername = 'ubuntu',
    [string] $ControlPlaneAddress = '192.168.0.128',
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin',
    [string[]] $WorkerAddresses = @('192.168.0.129', '192.168.0.130')
)

$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PSScriptRoot 'nginx.yaml'

foreach ($commandName in @('ssh', 'scp', 'ssh-add')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "$commandName is not installed or is not available on PATH."
    }
}

foreach ($requiredPath in @($PrivateKeyPath, $manifestPath)) {
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

& scp @sshOptions $manifestPath "${remote}:/tmp/atap-nginx.yaml"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not copy the NGINX manifest to the control plane.'
}

$applyCommand = @(
    'kubectl apply --filename=/tmp/atap-nginx.yaml'
    '&& kubectl rollout status deployment/nginx --namespace=learning --timeout=180s'
    '&& rm -f /tmp/atap-nginx.yaml'
) -join ' '

& ssh @sshOptions $remote $applyCommand
if ($LASTEXITCODE -ne 0) {
    throw 'NGINX deployment or scheduling validation failed.'
}

$podJson = & ssh @sshOptions $remote 'kubectl get pods --namespace=learning --selector=app=nginx --output=json'
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the NGINX Pods.'
}

$pods = ($podJson | ConvertFrom-Json).items
$readyPods = @(
    $pods | Where-Object {
        $_.status.phase -eq 'Running' -and
        @($_.status.containerStatuses | Where-Object { -not $_.ready }).Count -eq 0
    }
)
$scheduledNodes = @($readyPods.spec.nodeName | Sort-Object -Unique)
if ($readyPods.Count -ne 2 -or $scheduledNodes.Count -ne 2) {
    throw 'Expected two ready NGINX Pods scheduled on two distinct nodes.'
}

foreach ($workerAddress in $WorkerAddresses) {
    $response = Invoke-WebRequest -Uri "http://${workerAddress}:30080/" -TimeoutSec 15 -UseBasicParsing
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'Welcome to nginx') {
        throw "NGINX NodePort validation failed through ${workerAddress}:30080."
    }
}

& ssh @sshOptions $remote "kubectl get pods --namespace=learning --selector=app=nginx --output=custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready --no-headers"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the final NGINX Pod placement.'
}

Write-Output 'NGINX is running across both workers and is reachable through NodePort 30080.'
