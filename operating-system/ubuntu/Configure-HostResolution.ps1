[CmdletBinding()]
param(
    [string] $OperatorUsername = 'ubuntu',
    [string] $PrivateKeyPath = 'D:\Homelab\keys\homelab-admin'
)

$ErrorActionPreference = 'Stop'

$nodes = [ordered]@{
    'k8s-cp-01' = '192.168.0.128'
    'k8s-worker-01' = '192.168.0.129'
    'k8s-worker-02' = '192.168.0.130'
}

$templatePath = Join-Path -Path $PSScriptRoot -ChildPath 'templates\hosts.debian.tmpl'
$windowsHostsPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\drivers\etc\hosts'
$managedBlockStart = '# BEGIN ATap.Datacenter Kubernetes nodes'
$managedBlockEnd = '# END ATap.Datacenter Kubernetes nodes'

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

if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Guest hosts template not found: $templatePath"
}

$principal = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session so it can update the Windows hosts file.'
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

foreach ($entry in $nodes.GetEnumerator()) {
    $destination = "$OperatorUsername@$($entry.Value):/tmp/atap-hosts.debian.tmpl"
    Invoke-ExternalCommand -Command 'scp' -Arguments ($sshOptions + @($templatePath, $destination))

    $installCommand = @(
        'sudo -n install -o root -g root -m 0644'
        '/tmp/atap-hosts.debian.tmpl'
        '/etc/cloud/templates/hosts.debian.tmpl'
        '&& sudo -n cloud-init single --name update_etc_hosts --frequency always'
        '&& rm -f /tmp/atap-hosts.debian.tmpl'
    ) -join ' '

    Invoke-ExternalCommand -Command 'ssh' -Arguments (
        $sshOptions + @("$OperatorUsername@$($entry.Value)", $installCommand)
    )
}

$newLine = [Environment]::NewLine
$managedLines = @($managedBlockStart)
foreach ($entry in $nodes.GetEnumerator()) {
    $managedLines += "$($entry.Value) $($entry.Key)"
}
$managedLines += $managedBlockEnd
$managedBlock = $managedLines -join $newLine

$windowsHostsContent = [IO.File]::ReadAllText($windowsHostsPath)
$managedPattern = '(?ms)^' + [regex]::Escape($managedBlockStart) +
    '\r?\n.*?^' + [regex]::Escape($managedBlockEnd) + '\r?\n?'
$unmanagedContent = [regex]::Replace($windowsHostsContent, $managedPattern, '').TrimEnd()
$updatedContent = $unmanagedContent + $newLine + $newLine + $managedBlock + $newLine
$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($windowsHostsPath, $updatedContent, $utf8WithoutBom)
Clear-DnsClientCache

foreach ($entry in $nodes.GetEnumerator()) {
    $localAddresses = [Net.Dns]::GetHostAddresses($entry.Key).IPAddressToString
    if ($localAddresses -notcontains $entry.Value) {
        throw "Windows did not resolve $($entry.Key) to $($entry.Value)."
    }
}

foreach ($source in $nodes.GetEnumerator()) {
    foreach ($target in $nodes.GetEnumerator()) {
        $validationCommand = "getent ahostsv4 '$($target.Key)' | awk '{print `$1}' | grep -Fxq '$($target.Value)'"
        Invoke-ExternalCommand -Command 'ssh' -Arguments (
            $sshOptions + @("$OperatorUsername@$($source.Value)", $validationCommand)
        )
    }
}

Write-Output 'Host resolution is configured and validated on Windows and all Ubuntu nodes.'
