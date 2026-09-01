[CmdletBinding()]
param(
    [string] $VarFile,
    [string[]] $NewNode = @(),
    [switch] $AutoApprove
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VarFile)) {
    $VarFile = Join-Path -Path $PSScriptRoot -ChildPath 'terraform.tfvars'
}

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    throw 'HashiCorp Terraform is not installed or is not available on PATH.'
}

if (-not (Test-Path -LiteralPath $VarFile -PathType Leaf)) {
    throw "Terraform variable file not found: $VarFile. Copy terraform.tfvars.example and configure the operator SSH public key."
}

foreach ($nodeKey in $NewNode) {
    if ($nodeKey -notmatch '^[a-z][a-z0-9_]*$') {
        throw "Invalid Terraform node key: $nodeKey"
    }
}

function Invoke-Terraform {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    & terraform @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "terraform $($Arguments[0]) failed with exit code $LASTEXITCODE."
    }
}

function New-TerraformPlan {
    param(
        [Parameter(Mandatory)]
        [string] $PlanPath,
        [string[]] $ExtraArguments = @()
    )

    $arguments = @(
        'plan'
        '-no-color'
        '-detailed-exitcode'
        "-var-file=$VarFile"
        "-out=$PlanPath"
    ) + $ExtraArguments

    & terraform @arguments | Out-Host
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 1) {
        throw 'terraform plan failed.'
    }

    return $exitCode
}

function Confirm-Apply {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($AutoApprove) {
        return
    }

    $response = Read-Host "$Message [y/N]"
    if ($response -notmatch '^(?i:y|yes)$') {
        throw 'Terraform apply cancelled.'
    }
}

$offPlanPath = Join-Path -Path $PSScriptRoot -ChildPath '.deploy-off.tfplan'
$applyPlanPath = Join-Path -Path $PSScriptRoot -ChildPath '.deploy-apply.tfplan'
$finalPlanPath = Join-Path -Path $PSScriptRoot -ChildPath '.deploy-final.tfplan'
$planPaths = @($offPlanPath, $applyPlanPath, $finalPlanPath)

Push-Location $PSScriptRoot
try {
    Invoke-Terraform -Arguments @('init', '-upgrade=false', '-input=false')
    Invoke-Terraform -Arguments @('fmt', '-check')
    Invoke-Terraform -Arguments @('validate')

    if ($NewNode.Count -gt 0) {
        if (-not (Get-Command Set-VM -ErrorAction SilentlyContinue)) {
            throw 'The Hyper-V PowerShell module is required when provisioning a new node.'
        }

        $offValues = $NewNode | ForEach-Object { "$_=`"Off`"" }
        $offMap = '{' + ($offValues -join ',') + '}'
        $offPlanExitCode = New-TerraformPlan `
            -PlanPath $offPlanPath `
            -ExtraArguments @("-var=node_desired_states=$offMap")

        if ($offPlanExitCode -eq 2) {
            Confirm-Apply -Message 'Apply the plan that creates new nodes in the Off state?'
            Invoke-Terraform -Arguments @('apply', '-no-color', $offPlanPath)
        }

        $nodeOutputs = Invoke-Terraform -Arguments @('output', '-json', 'nodes')
        $nodes = ($nodeOutputs -join [Environment]::NewLine) | ConvertFrom-Json

        foreach ($nodeKey in $NewNode) {
            $nodeProperty = $nodes.PSObject.Properties[$nodeKey]
            if (-not $nodeProperty) {
                throw "Terraform output does not contain node key: $nodeKey"
            }

            $vmName = $nodeProperty.Value.name
            $vm = Get-VM -Name $vmName -ErrorAction Stop
            if ($vm.State -ne 'Off') {
                throw "New VM $vmName must be Off before automatic checkpoints are disabled."
            }

            $checkpoints = @(Get-VMSnapshot -VMName $vmName -ErrorAction SilentlyContinue)
            if ($checkpoints.Count -ne 0) {
                throw "New VM $vmName already has a checkpoint; inspect it before continuing."
            }

            Set-VM -Name $vmName -AutomaticCheckpointsEnabled $false
        }
    }

    $applyPlanExitCode = New-TerraformPlan -PlanPath $applyPlanPath
    if ($applyPlanExitCode -eq 2) {
        Confirm-Apply -Message 'Apply the Terraform infrastructure plan?'
        Invoke-Terraform -Arguments @('apply', '-no-color', $applyPlanPath)
    }

    # Guest boot updates computed values such as IP addresses and VHDX file
    # size. Record those observations without changing remote infrastructure.
    Invoke-Terraform -Arguments @(
        'apply'
        '-refresh-only'
        '-auto-approve'
        '-no-color'
        "-var-file=$VarFile"
    )

    $finalPlanExitCode = New-TerraformPlan -PlanPath $finalPlanPath
    if ($finalPlanExitCode -ne 0) {
        throw 'Terraform did not converge. Review the final plan before applying further changes.'
    }

    Invoke-Terraform -Arguments @('output')
}
finally {
    Pop-Location

    foreach ($planPath in $planPaths) {
        if (Test-Path -LiteralPath $planPath) {
            Remove-Item -LiteralPath $planPath -Force
        }
    }
}
