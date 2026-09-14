# Start the full POC: observability + banking + insurance + retail-orders.
# Fresh-clone safe: bootstraps missing .env files from .env.example and
# exports the root tokens so all three stacks always agree (FR-06).
# Usage: .\scripts\up.ps1 [-NoBuild]
param(
  [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Obs = Join-Path $Root "docker-compose.yml"
$BankDir = Join-Path $Root "custumers\digital-banking-services"
$InsDir = Join-Path $Root "custumers\insurance-services"
$RetailDir = Join-Path $Root "custumers\retail-orders-services"

function Copy-IfMissing($Example, $Target) {
  if (-not (Test-Path -LiteralPath $Target)) {
    if (Test-Path -LiteralPath $Example) {
      Copy-Item -LiteralPath $Example -Destination $Target
      Write-Host "created $Target from example (edit it for real secrets)"
    } else {
      Write-Warning "neither $Target nor $Example exists, continuing with compose defaults"
    }
  }
}

function Get-EnvValue($File, $Key) {
  $line = Select-String -LiteralPath $File -Pattern "^\s*(export\s+)?$Key=" -ErrorAction SilentlyContinue |
    Select-Object -Last 1
  if ($null -eq $line) { return "" }
  $val = $line.Line -replace "^\s*(export\s+)?$Key=", ""
  $val = $val.Trim().Trim("'", '"')
  # strip trailing inline comment left outside quotes (simple case)
  $val = ($val -split '\s#', 2)[0].Trim().Trim("'", '"')
  return $val
}

function Wait-Tcp($Port, $Tries = 30) {
  for ($i = 1; $i -le $Tries; $i++) {
    try {
      $c = New-Object Net.Sockets.TcpClient
      $iar = $c.BeginConnect("127.0.0.1", $Port, $null, $null)
      if ($iar.AsyncWaitHandle.WaitOne(2000) -and $c.Connected) { $c.Close(); return $true }
      $c.Close()
    } catch { }
    Start-Sleep -Seconds 2
  }
  return $false
}

# 1. Bootstrap .env files (all gitignored, only *.example is committed).
Copy-IfMissing (Join-Path $Root ".env.example") (Join-Path $Root ".env")
Copy-IfMissing (Join-Path $BankDir ".env.example") (Join-Path $BankDir ".env")
Copy-IfMissing (Join-Path $InsDir ".env.example") (Join-Path $InsDir ".env")
Copy-IfMissing (Join-Path $RetailDir ".env.example") (Join-Path $RetailDir ".env")

# 2. Single source of truth: tokens come from the ROOT .env and are exported
#    so `docker compose` interpolation in the client stacks cannot drift.
$RootEnv = Join-Path $Root ".env"
$env:BANKING_TOKEN = Get-EnvValue $RootEnv "BANKING_TOKEN"
$env:INSURANCE_TOKEN = Get-EnvValue $RootEnv "INSURANCE_TOKEN"
$env:RETAIL_TOKEN = Get-EnvValue $RootEnv "RETAIL_TOKEN"
if ([string]::IsNullOrWhiteSpace($env:BANKING_TOKEN) -or [string]::IsNullOrWhiteSpace($env:INSURANCE_TOKEN) -or [string]::IsNullOrWhiteSpace($env:RETAIL_TOKEN)) {
  throw "BANKING_TOKEN / INSURANCE_TOKEN / RETAIL_TOKEN missing in $RootEnv. Copy .env.example to .env and set all three tokens."
}
# Prod hardening #4: Grafana admin comes from the same root .env.
$env:GF_ADMIN_USER = Get-EnvValue $RootEnv "GF_ADMIN_USER"
$env:GF_ADMIN_PASSWORD = Get-EnvValue $RootEnv "GF_ADMIN_PASSWORD"
if ([string]::IsNullOrWhiteSpace($env:GF_ADMIN_USER) -or [string]::IsNullOrWhiteSpace($env:GF_ADMIN_PASSWORD)) {
  throw "GF_ADMIN_USER / GF_ADMIN_PASSWORD missing in $RootEnv. Set both values before starting."
}

Write-Host "NOTE: storage isolation is now enforced (Loki/Mimir/Tempo multitenancy)."
Write-Host "If upgrading from a pre-multitenancy stack, run .\scripts\down.ps1 -Volumes once - old data under tenant fake/anonymous is invisible."

# 2b. Local simulation TLS cert (self-signed *.localhost). Regenerate if missing.
$CertDir = Join-Path $Root "observability\traefik\certs"
if (-not (Test-Path (Join-Path $CertDir "edge.crt")) -or -not (Test-Path (Join-Path $CertDir "edge.key"))) {
  Write-Host "== generating local edge TLS cert (*.localhost, simulation only) =="
  New-Item -ItemType Directory -Force -Path $CertDir | Out-Null
  & openssl req -x509 -newkey rsa:2048 -keyout (Join-Path $CertDir "edge.key") -out (Join-Path $CertDir "edge.crt") -days 365 -nodes -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,DNS:*.localhost,DNS:banking-otlp.localhost,DNS:banking-http-otlp.localhost,DNS:insurance-otlp.localhost,DNS:insurance-http-otlp.localhost,DNS:retail-otlp.localhost,DNS:retail-http-otlp.localhost,DNS:grafana.localhost,DNS:traefik"
  Copy-Item (Join-Path $CertDir "edge.crt") (Join-Path $CertDir "ca.crt") -Force
}

# 2c. Host DNS check for browser/k6.
foreach ($h in @("grafana.localhost", "banking-otlp.localhost", "insurance-otlp.localhost", "retail-otlp.localhost")) {
  try { [void][Net.Dns]::GetHostEntry($h) } catch { Write-Warning "$h does not resolve — add '127.0.0.1 $h' to C:\Windows\System32\drivers\etc\hosts" }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "docker not found in PATH." }

function Invoke-ComposeUp($ComposeFile) {
  # NOTE: pass ALL args as one array. Splatting a single string (e.g. "@"--build"")
  # makes PS 5.1 enumerate its characters to a native command ("no such service: -").
  $composeArgs = @("compose", "-f", $ComposeFile, "up", "-d")
  if (-not $NoBuild) { $composeArgs += "--build" }
  & docker @composeArgs
}

# 3. Start in dependency order: gateway first, clients second.
Write-Host "== observability =="
Invoke-ComposeUp $Obs
Write-Host "== banking =="
Invoke-ComposeUp (Join-Path $BankDir "docker-compose.yml")
Write-Host "== insurance =="
Invoke-ComposeUp (Join-Path $InsDir "docker-compose.yml")
Write-Host "== retail-orders =="
Invoke-ComposeUp (Join-Path $RetailDir "docker-compose.yml")

# 4. Traefik is the public platform surface: poll TCP from the host instead.
foreach ($p in 443, 8080, 8083, 8084) {
  if (Wait-Tcp $p) { Write-Host "ok 127.0.0.1:$p" }
  else { Write-Warning "127.0.0.1:$p not reachable yet (see docker compose ps/logs)" }
}

@'

All stacks started:
  Grafana       https://grafana.localhost (Traefik local certificate may require browser approval)
  Banking API   http://localhost:8080
  Fraud svc     http://localhost:8081
  Insurance API http://localhost:8083  (container :8080)
  Risk svc      http://localhost:8082
  Retail API    http://localhost:8084  (container :8080, via client-collector-retail-orders)
  OTLP edge      https://banking-otlp.localhost and https://insurance-otlp.localhost
                 https://retail-otlp.localhost (client collector only)

Useful:
  .\scripts\down.ps1                # stop everything
  docker compose -f docker-compose.yml logs -f otel-gateway
'@
