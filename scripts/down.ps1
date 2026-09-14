# Stop the full POC (reverse order of up.ps1).
# Usage: .\scripts\down.ps1 [-Volumes]   # also removes named volumes
param(
  [switch]$Volumes
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Obs = Join-Path $Root "docker-compose.yml"
$BankDir = Join-Path $Root "custumers\digital-banking-services"
$InsDir = Join-Path $Root "custumers\insurance-services"
$RetailDir = Join-Path $Root "custumers\retail-orders-services"

function Get-EnvValue($File, $Key) {
  $line = Select-String -LiteralPath $File -Pattern "^\s*(export\s+)?$Key=" -ErrorAction SilentlyContinue |
    Select-Object -Last 1
  if ($null -eq $line) { return "" }
  $val = $line.Line -replace "^\s*(export\s+)?$Key=", ""
  $val = $val.Trim().Trim("'", '"')
  $val = ($val -split '\s#', 2)[0].Trim().Trim("'", '"')
  return $val
}

# down only needs interpolation to succeed, not real secrets.
$RootEnv = Join-Path $Root ".env"
$env:BANKING_TOKEN = Get-EnvValue $RootEnv "BANKING_TOKEN"
$env:INSURANCE_TOKEN = Get-EnvValue $RootEnv "INSURANCE_TOKEN"
$env:RETAIL_TOKEN = Get-EnvValue $RootEnv "RETAIL_TOKEN"
$env:GF_ADMIN_USER = Get-EnvValue $RootEnv "GF_ADMIN_USER"
$env:GF_ADMIN_PASSWORD = Get-EnvValue $RootEnv "GF_ADMIN_PASSWORD"
if ([string]::IsNullOrWhiteSpace($env:BANKING_TOKEN)) { $env:BANKING_TOKEN = "placeholder-for-down" }
if ([string]::IsNullOrWhiteSpace($env:INSURANCE_TOKEN)) { $env:INSURANCE_TOKEN = "placeholder-for-down" }
if ([string]::IsNullOrWhiteSpace($env:RETAIL_TOKEN)) { $env:RETAIL_TOKEN = "placeholder-for-down" }
if ([string]::IsNullOrWhiteSpace($env:GF_ADMIN_USER)) { $env:GF_ADMIN_USER = "placeholder-for-down" }
if ([string]::IsNullOrWhiteSpace($env:GF_ADMIN_PASSWORD)) { $env:GF_ADMIN_PASSWORD = "placeholder-for-down" }

function Invoke-ComposeDown($ComposeFile) {
  # NOTE: pass ALL args as one array — splatting a single string makes
  # PS 5.1 enumerate its characters to a native command (see up.ps1).
  $composeArgs = @("compose", "-f", $ComposeFile, "down")
  if ($Volumes) { $composeArgs += "-v" }
  & docker @composeArgs
}

Invoke-ComposeDown (Join-Path $RetailDir "docker-compose.yml")
Invoke-ComposeDown (Join-Path $InsDir "docker-compose.yml")
Invoke-ComposeDown (Join-Path $BankDir "docker-compose.yml")
Invoke-ComposeDown $Obs

Write-Host "All stacks stopped."
