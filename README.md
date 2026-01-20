<<<<<<< HEAD
\# Asterisk Project



\## Overview

Asterisk + (Docker/Compose) 기반의 통화/녹취/연동 실습 프로젝트



\## How to Run

```bash

docker compose up -d



=======
# Asterisk Docker (Auto advertise address)

This project runs Asterisk in Docker and automatically sets the SIP/SDP advertise address
so you do **not** have to edit `pjsip.conf` when your network changes.

## What was changed

- `asterisk/pjsip.conf.tmpl`: template file. `__ADVERTISE_ADDR__` and `__LOCAL_NETS__` are
  replaced at container start.
- `docker-entrypoint.sh`: generates `/etc/asterisk/pjsip.conf` from the template before starting Asterisk.
- `scripts/set-env.ps1`: writes/updates `.env` automatically.
  - Detects current IPv4 + prefix length
  - Generates correct CIDR (e.g. `192.168.10.0/24`)
  - Avoids Docker ranges (e.g. `172.16.0.0/12`) to prevent SDP advertising container IP on Windows Docker Desktop
- `.env.example`: ASCII-only, safe encoding.

## Quick start (Windows / PowerShell)

1) Open PowerShell in the `asterisk-docker` folder.

2) Create `.env` and auto-fill it:

```powershell
copy .env.example .env
powershell -ExecutionPolicy Bypass -File .\scripts\set-env.ps1
```

(Optional) Remote testing (LTE / different Wi-Fi) using Tailscale:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-env.ps1 -UseTailscale
```

3) Start Asterisk:

```powershell
docker compose up -d
docker compose ps
```

4) Zoiper settings (example)

- Host: value of `ADVERTISE_ADDR` in `.env`
- Port: `5060`
- Transport: `UDP`
- Accounts:
  - 2001 / pass2001
  - 2002 / pass2002

Recommended (to avoid no-audio cases):
- SRTP/Media encryption: OFF
- ICE/STUN: OFF for same-network testing
- Codecs: enable PCMU/PCMA (G.711)

5) Test calls

- Echo test: dial `600`
- Extension test: `2001` <-> `2002`

Recordings are written to the `recordings/` folder.

## Debug

```powershell
docker exec -it asterisk asterisk -rvvvvv
```

In Asterisk CLI:

```text
pjsip set logger on
rtp set debug on
```

## Firewall (Windows)

Allow inbound UDP ports (run in elevated PowerShell):

```powershell
New-NetFirewallRule -DisplayName "Asterisk SIP UDP 5060" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 5060
New-NetFirewallRule -DisplayName "Asterisk RTP UDP 10000-10100" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 10000-10100
```
>>>>>>> 9ea7490 (fix: NAT/SDP 광고 안정화 및 .env 자동 세팅 스크립트 추가(network 변경에도 동작))
