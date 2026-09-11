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

function Invoke-ComposeDown($ComposeFile) {
  # NOTE: pass ALL args as one array — splatting a single string makes
  # PS 5.1 enumerate its characters to a native command (see up.ps1).
  $composeArgs = @("compose", "-f", $ComposeFile, "down")
  if ($Volumes) { $composeArgs += "-v" }
  & docker @composeArgs
}

Invoke-ComposeDown (Join-Path $InsDir "docker-compose.yml")
Invoke-ComposeDown (Join-Path $BankDir "docker-compose.yml")
Invoke-ComposeDown $Obs

Write-Host "All stacks stopped."
