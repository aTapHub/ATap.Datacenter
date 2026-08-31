[CmdletBinding()]
param(
    [string] $VarFile
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 does not populate $PSScriptRoot early enough to use it
# reliably in a parameter default expression. Resolve the default after binding.
if ([string]::IsNullOrWhiteSpace($VarFile)) {
    $VarFile = Join-Path -Path $PSScriptRoot -ChildPath 'local.pkrvars.hcl'
}

if (-not (Get-Command packer -ErrorAction SilentlyContinue)) {
    throw 'HashiCorp Packer is not installed or is not available on PATH.'
}

if (-not (Get-Command Get-VMHost -ErrorAction SilentlyContinue)) {
    throw 'The Hyper-V PowerShell module is not available on this machine.'
}

if (-not (Test-Path -LiteralPath $VarFile -PathType Leaf)) {
    throw "Packer variable file not found: $VarFile. Copy local.pkrvars.hcl.example and provide the build SSH key."
}

$isoTool = Get-Command oscdimg, xorriso, mkisofs -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $isoTool) {
    throw 'Packer needs oscdimg, xorriso, or mkisofs on PATH to create the cidata ISO.'
}

$switch = Get-VMSwitch -Name 'Kubernetes' -ErrorAction SilentlyContinue
if (-not $switch) {
    throw "The required Hyper-V switch 'Kubernetes' does not exist."
}

if ($switch.SwitchType -ne 'External') {
    throw "The 'Kubernetes' switch exists but is not an external switch."
}

$requiredDirectories = @(
    'D:\Homelab\images',
    'D:\Homelab\packer-temp'
)

foreach ($directory in $requiredDirectories) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

Push-Location $PSScriptRoot
try {
    & packer init .
    if ($LASTEXITCODE -ne 0) { throw 'packer init failed.' }

    & packer fmt -check .
    if ($LASTEXITCODE -ne 0) { throw 'packer fmt -check failed.' }

    & packer validate "-var-file=$VarFile" .
    if ($LASTEXITCODE -ne 0) { throw 'packer validate failed.' }

    & packer build "-var-file=$VarFile" .
    if ($LASTEXITCODE -ne 0) { throw 'packer build failed.' }
}
finally {
    Pop-Location
}
