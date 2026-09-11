# Generate sustained realistic traffic with k6 (grafana/k6 in Docker, no local install).
# Usage: .\scripts\load-k6.ps1 [-DurationMin 5] [-Vus 10] [-Chaos off|latency|rejects]
#   -DurationMin  steady-load minutes (ramp is +2m, or +1m when <= 2)
#   -Vus          virtual users PER scenario (banking + insurance run together)
#   -Chaos        off (default) | latency (2.5s downstream delay, trips the 2s
#                 timeout) | rejects (30% chaos_forced rejections)
param(
  [int]$DurationMin = 5,
  [int]$Vus = 10,
  [ValidateSet("off", "latency", "rejects")]
  [string]$Chaos = "off",
  [switch]$h,
  [switch]$Help
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$BankCompose = Join-Path $Root "custumers\digital-banking-services\docker-compose.yml"
$InsCompose = Join-Path $Root "custumers\insurance-services\docker-compose.yml"
$LoadDir = Join-Path $Root "load"

if ($h -or $Help) {
  @'
Usage: .\scripts\load-k6.ps1 [-DurationMin 5] [-Vus 10] [-Chaos off|latency|rejects]

  -DurationMin  steady-load minutes (default 5; ramp adds +2m, or +1m when <= 2)
  -Vus          virtual users per scenario (default 10; banking + insurance run together)
  -Chaos        off | latency | rejects (default off)
                latency: CHAOS_LATENCY_MS=2500 on fraud/risk-service (trips 2s timeout)
                rejects: CHAOS_REJECT_RATE=0.3 on fraud/risk-service (reject storm)

Examples:
  .\scripts\load-k6.ps1 -DurationMin 1 -Vus 2
  .\scripts\load-k6.ps1 -DurationMin 5 -Vus 10 -Chaos latency

Notes:
  k6 runs in Docker (grafana/k6) on the default bridge network via
  http://host.docker.internal:8080|:8083 (Docker Desktop resolves it;
  native-Linux Engine may need extra_hosts, see compose comments).
'@
  exit 0
}

if ($DurationMin -lt 1) { throw "-DurationMin must be >= 1." }
if ($Vus -lt 1) { throw "-Vus must be >= 1." }

# Ramp scales down for short runs so `-DurationMin 1` stays a quick smoke test.
$RampMin = 2
if ($DurationMin -le 2) { $RampMin = 1 }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "docker not found in PATH." }
if (-not (Test-Path -LiteralPath (Join-Path $LoadDir "poc-load.js"))) {
  throw "load/poc-load.js not found. Run from the repo root."
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

# Single source of truth (mirrors up.ps1): chaos `compose up -d` recreates
# fraud/risk-service, so the root tokens must be exported or compose falls
# back to dir-.env placeholders and the gateway rejects their telemetry.
$RootEnv = Join-Path $Root ".env"
$env:BANKING_TOKEN = Get-EnvValue $RootEnv "BANKING_TOKEN"
$env:INSURANCE_TOKEN = Get-EnvValue $RootEnv "INSURANCE_TOKEN"
if ([string]::IsNullOrWhiteSpace($env:BANKING_TOKEN) -or [string]::IsNullOrWhiteSpace($env:INSURANCE_TOKEN)) {
  throw "BANKING_TOKEN / INSURANCE_TOKEN missing in $RootEnv. Copy .env.example to .env and set both tokens."
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

function Set-Chaos($Latency, $Rate) {
  # NOTE: pass ALL args as one array. Splatting a single string makes
  # PS 5.1 enumerate its characters to a native command (see up.ps1).
  # No rebuild needed: fraud/risk-service read CHAOS_* envs on restart.
  Write-Host "== chaos CHAOS_LATENCY_MS=$Latency CHAOS_REJECT_RATE=$Rate =="
  $env:CHAOS_LATENCY_MS = $Latency
  $env:CHAOS_REJECT_RATE = $Rate
  try {
    $a = @("compose", "-f", $BankCompose, "up", "-d", "fraud-service"); & docker @a
    $b = @("compose", "-f", $InsCompose, "up", "-d", "risk-service"); & docker @b
  } finally {
    Remove-Item Env:\CHAOS_LATENCY_MS -ErrorAction SilentlyContinue
    Remove-Item Env:\CHAOS_REJECT_RATE -ErrorAction SilentlyContinue
  }
}

Write-Host "== banking =="
if (Wait-Tcp 8080 5) { Write-Host "ok 127.0.0.1:8080 (banking-api)" }
else { Write-Warning "127.0.0.1:8080 not reachable — start the stack first: .\scripts\up.ps1" }
Write-Host "== insurance =="
if (Wait-Tcp 8083 5) { Write-Host "ok 127.0.0.1:8083 (insurance-api)" }
else { Write-Warning "127.0.0.1:8083 not reachable — start the stack first: .\scripts\up.ps1" }

# Chaos set-up (no rebuild needed: services read CHAOS_* envs on restart).
if ($Chaos -eq "latency") { Set-Chaos "2500" "0" }
elseif ($Chaos -eq "rejects") { Set-Chaos "0" "0.3" }

$K6Exit = 0
try {
  Write-Host "== k6 (banking + insurance, Vus=$Vus steady=${DurationMin}m ramp=${RampMin}m chaos=$Chaos) =="
  # NOTE: full arg array again — never splat a single string (see up.ps1).
  $k6Args = @(
    "run", "--rm", "-i",
    "--network", "bridge",
    "-e", "BANKING_URL=http://host.docker.internal:8080",
    "-e", "INSURANCE_URL=http://host.docker.internal:8083",
    "-e", "VUS=$Vus",
    "-e", "RAMP_MIN=$RampMin",
    "-e", "STEADY_MIN=$DurationMin",
    "-e", "CHAOS_MODE=$Chaos",
    "-v", "${LoadDir}:/scripts:ro",
    "grafana/k6", "run", "/scripts/poc-load.js"
  )
  & docker @k6Args
  $K6Exit = $LASTEXITCODE
} finally {
  # Always restore 0/0 afterwards, even when k6 fails.
  if ($Chaos -ne "off") {
    Write-Host "== chaos restore (0/0) =="
    Set-Chaos "0" "0"
  }
}

Write-Host ""
Write-Host "Endpoints: Banking API http://localhost:8080, Insurance API http://localhost:8083,"
Write-Host "  Grafana http://localhost:3000, OTLP banking 4317/4318 | insurance 4320/4321."
exit $K6Exit
