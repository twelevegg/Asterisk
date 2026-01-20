param(
  [switch]$UseTailscale,
  [string]$EnvPath = ".env",
  [string]$EnvExamplePath = ".env.example"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AdvertiseIPv4 {
  param([switch]$PreferTailscale)

  # 1) Tailscale IP (remote test)
  if ($PreferTailscale) {
    $ts = Get-NetIPConfiguration |
      Where-Object { $_.IPv4Address -and ($_.InterfaceAlias -like "*Tailscale*") } |
      Select-Object -First 1

    if (-not $ts -or -not $ts.IPv4Address) {
      throw "Tailscale IPv4를 찾지 못했습니다. Tailscale이 연결되어 있는지 확인하세요."
    }
    return $ts.IPv4Address[0].IPAddress
  }

  # 2) Default route (0.0.0.0/0) interface IPv4
  $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Sort-Object -Property RouteMetric, InterfaceMetric |
    Select-Object -First 1

  if ($route) {
    $ipObj = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress -and $_.IPAddress -ne "127.0.0.1" } |
      Sort-Object -Property PrefixLength -Descending |
      Select-Object -First 1

    if ($ipObj) { return $ipObj.IPAddress }
  }

  # 3) Fallback: first non-loopback IPv4
  $ipObj2 = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -and $_.IPAddress -ne "127.0.0.1" -and $_.InterfaceAlias -notmatch "Loopback" } |
    Select-Object -First 1

  if ($ipObj2) { return $ipObj2.IPAddress }

  throw "유효한 IPv4를 찾지 못했습니다."
}

function Upsert-EnvKey {
  param([string[]]$Lines, [string]$Key, [string]$Value)

  $pattern = "^\s*{0}\s*=" -f [regex]::Escape($Key)
  $found = $false

  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match $pattern) {
      $Lines[$i] = "$Key=$Value"
      $found = $true
      break
    }
  }

  if (-not $found) { $Lines += "$Key=$Value" }
  return ,$Lines
}

# Ensure .env exists
if (-not (Test-Path $EnvPath)) {
  if (Test-Path $EnvExamplePath) {
    Copy-Item $EnvExamplePath $EnvPath -Force
  } else {
    "ADVERTISE_ADDR=`nLOCAL_NETS=`n" | Set-Content -Path $EnvPath -Encoding UTF8
  }
}

$envLines = Get-Content -Path $EnvPath -Encoding UTF8

$advertise = Get-AdvertiseIPv4 -PreferTailscale:$UseTailscale

# IMPORTANT:
# - Windows Docker Desktop 환경에서 Docker 대역(172.16.0.0/12 등)을 local_net에 넣으면
#   SDP가 컨테이너 IP(172.19.x.x)로 광고되어 무음/0초 녹취가 재발할 수 있습니다.
# - 따라서 local_net은 "클라이언트가 존재할 법한 대역"만 넓게 포함합니다.
$localNets = "192.168.0.0/16,10.0.0.0/8,100.64.0.0/10"

$envLines = Upsert-EnvKey -Lines $envLines -Key "ADVERTISE_ADDR" -Value $advertise
$envLines = Upsert-EnvKey -Lines $envLines -Key "LOCAL_NETS" -Value $localNets

$envLines | Set-Content -Path $EnvPath -Encoding UTF8

Write-Host ("[OK] ADVERTISE_ADDR={0}" -f $advertise)
Write-Host ("[OK] LOCAL_NETS={0}" -f $localNets)
