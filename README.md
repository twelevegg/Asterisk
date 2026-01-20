# Asterisk (Docker) 실행 기록/가이드 (Windows + Docker Desktop / Zoiper)

Windows + Docker Desktop에서 Asterisk 20을 Docker로 실행하는 구성임.  
“SIP는 되는데 음성(RTP)이 안 들리는 무음/편도 음성”이 자주 터져서, 그거 재발 안 하게 구조를 잡아둔 상태임.

목표는 아래 3개였음.
- 네트워크 바뀌어도 `pjsip.conf` 같은 파일을 직접 수정 안 하게 만들기
- `.env` 자동 세팅으로 실행 절차 단순화하기
- Docker Desktop 환경에서 SDP가 컨테이너 IP(172.19.x.x)로 광고되어 무음 나는 거 방지하기

---

## 목차
- 왜 이런 구성이 필요한지
- 지금까지 터졌던 문제/원인/해결
- 처음 압축 풀고 실행하는 절차
- Zoiper 설정
- 테스트 방법
- 녹취 확인
- 트러블슈팅/디버깅
- AWS 올릴 때 참고

---

## 왜 이런 구성이 필요한지

SIP 통화는 트래픽이 2개로 나뉨.

- SIP(신호): UDP 5060 (등록/발신/착신/끊기)
- RTP(음성): UDP 포트 범위 (여기선 10000–10100) (실제 음성 데이터)

SIP는 되는데 음성이 안 들리는 건 대부분 RTP 쪽에서 터지는 거임.

특히 Windows + Docker Desktop에서는 단말(Zoiper)이 Asterisk에서 `172.19.0.1`(Docker 게이트웨이)로 보이는 경우가 많음.  
이때 Asterisk가 SDP에 `c=IN IP4 172.19.0.2` 같은 컨테이너 내부 IP를 광고하면,
단말이 음성을 172.19로 보내려 해서 실제로는 도달 불가능 → 무음/0초 녹취 발생함.

그래서 이 저장소는 아래 정책으로 고정함.
- Asterisk가 SDP에 “클라이언트가 접근 가능한 주소”를 광고하도록 `ADVERTISE_ADDR` 사용함
- `local_net`에 Docker 대역(172.16/12 등) 안 넣음 (넣으면 Docker Desktop에서 local 오판해서 컨테이너 IP 광고함)
- `.env` 자동 생성/갱신 스크립트로 네트워크 변경 대응함

---

## 지금까지 터졌던 문제/원인/해결

### 1) SIP는 되는데 무음(양방향)/편도 음성/녹취 0초
- 증상: 통화 연결은 되는데 서로 목소리 안 들림. MixMonitor WAV도 0초거나 무음.
- 원인: SDP `c=IN IP4`가 컨테이너 IP(172.19.x.x)로 광고되는 경우 있었음. 또는 방화벽이 RTP UDP 막았음.
- 확인: `pjsip set logger on`으로 SDP 확인했음. `rtp set debug on`으로 RTP 흐름 확인했음.
- 해결:
  - `external_signaling_address`, `external_media_address`를 `ADVERTISE_ADDR`로 고정했음
  - `local_net`에서 Docker 대역 제외했음 (172.16/12 넣지 않음)
  - Windows 방화벽에서 UDP 5060, UDP 10000–10100 인바운드 허용했음
  - Zoiper에서 오디오 출력 장치 잘못 잡혀서 무음 난 적도 있었음(장치 고정으로 해결했음)

### 2) 네트워크 바뀔 때마다 IP 수정해야 하는 문제
- 증상: Wi-Fi 바뀌면 노트북 IP 바뀌어서 Zoiper/SDP 광고 주소가 계속 달라짐. 파일 직접 수정하는 게 번거로웠음.
- 해결: `.env`로 `ADVERTISE_ADDR`만 바꾸면 되게 만들고, 그걸 스크립트로 자동화했음.

### 3) set-env.ps1 오류( PrefixLength=-1 등 ) + `.env` 인코딩 깨짐
- 증상: PrefixLength가 -1로 들어와 UInt32 마스크 계산 터졌음. `.env` 첫 줄에 `癤?` 같은 문자(BOM)도 보였음.
- 해결:
  - `set-env.ps1`에서 CIDR 비트마스크 계산을 없애고 안정적으로 동작하게 고정했음
  - `LOCAL_NETS`는 넓게 `192.168.0.0/16,10.0.0.0/8,100.64.0.0/10`로 고정했음 (Docker 대역 제외 목적)
  - `.env`는 UTF-8 BOM 제거 명령으로 정리했음

---

## 처음 압축 풀고 실행하는 절차 (최소 루틴)

> 아래는 `docker-compose.yml` 있는 폴더(프로젝트 루트)에서 실행해야 함.

### 1) 폴더 이동
```
cd "C:\경로\asterisk-docker"
````

### 2) .env 생성

```
copy .env.example .env
```

### 3) .env 자동 세팅(수동 수정 없이)

```
powershell -ExecutionPolicy Bypass -File .\scripts\set-env.ps1
```

정상 출력 예:

* `[OK] ADVERTISE_ADDR=192.168.10.111`
* `[OK] LOCAL_NETS=192.168.0.0/16,10.0.0.0/8,100.64.0.0/10`

### 4) 컨테이너 실행

```
docker compose up -d
docker compose ps
```

`Up (healthy)`면 정상임.

---

## Zoiper 설정

`.env`의 `ADVERTISE_ADDR`를 Host로 넣으면 됨.

* Host/Domain: `ADVERTISE_ADDR` (예: 192.168.10.111)
* Port: 5060
* Transport: UDP
* Username/Password:

  * 2001 / pass2001
  * 2002 / pass2002

권장(무음 방지):

* SRTP / Media encryption: OFF
* ICE: OFF
* STUN: OFF (같은 Wi-Fi 테스트는 OFF가 보통 안정적임)
* Codec: PCMU(G.711 u-law), PCMA(G.711 a-law) 우선

---

## 테스트 방법

### 1) 에코 테스트

* 다이얼: `600`
* 내 목소리 돌아오면 RTP까지 정상임

### 2) 내선 통화

* 2001 → 2002, 2002 → 2001

---

## 녹취 확인

MixMonitor로 `recordings/`에 WAV 생성됨.

```
dir .\recordings
```

WAV가 0초/무음이면 보통 아래 중 하나임.

* RTP가 실제로 안 들어옴(방화벽/포트/SDP 광고 문제)
* SDP가 컨테이너 IP로 광고됨(172.19.x.x)
* Zoiper 오디오 장치/권한 문제

> 운영 관점에서는 `recordings/*.wav` 같은 실제 파일은 Git에 올리지 않는 게 나음.
> 폴더만 유지하려면 `.gitignore`로 wav 제외 + `.gitkeep` 방식 쓰면 됨.

---

## 트러블슈팅/디버깅

### A) 통화 연결은 되는데 무음/편도 음성

원인 후보:

* SDP 광고 IP가 이상함 (`c=IN IP4 172.19.x.x` 등)
* Windows 방화벽이 RTP UDP 막음
* Zoiper SRTP/ICE/STUN 켜짐
* PC Zoiper 오디오 출력 장치 틀림/음소거/권한 문제

#### Windows 방화벽(최초 1회, 관리자 PowerShell)

```powershell
New-NetFirewallRule -DisplayName "Asterisk SIP UDP 5060" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 5060
New-NetFirewallRule -DisplayName "Asterisk RTP UDP 10000-10100" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 10000-10100
```

### B) SDP/미디어 확인

Asterisk CLI 접속:

```
docker exec -it asterisk asterisk -rvvvvv
```

SIP/SDP 로그:

```
pjsip set logger on
```

RTP 흐름:

```
rtp set debug on
```

정상 기준:

* Asterisk가 단말에 보내는 `200 OK` SDP에서 `c=IN IP4 <ADVERTISE_ADDR>`가 떠야 함
* RTP debug에서 `Got RTP packet...` / `Sent RTP packet...`가 계속 떠야 함

Transport 설정 확인(호스트에서):

```
docker exec -it asterisk asterisk -rx "pjsip show transport transport-udp"
```

* `external_media_address`, `external_signaling_address`가 ADVERTISE_ADDR로 잡혀 있어야 함
* `local_net`에 Docker 대역(172.16/12 등)이 없어야 함

RTP 범위 확인:

```
docker exec -it asterisk asterisk -rx "rtp show settings"
```

---

## AWS 올릴 때 참고

운영은 “주소를 고정”시키는 게 핵심임.

추천 구성:

* EC2 + Elastic IP(EIP)로 공인 IP 고정
* Route53 도메인 연결(sip.example.com 같은 거)
* ADVERTISE_ADDR를 EIP(또는 고정 도메인에 매핑된 IP)로 고정 주입
* SG 인바운드:

  * UDP 5060
  * UDP 10000–10100 (또는 더 넓게)

규모/보안 요구 커지면 SBC(Kamailio/OpenSIPS) 전면 배치도 고려하면 됨.

---

## 폴더 구조

* `docker-compose.yml` : SIP/RTP 포트 매핑 및 서비스 정의
* `.env.example` / `.env` : 광고 주소/로컬 네트워크 값
* `scripts/set-env.ps1` : 네트워크 바뀌어도 `.env` 자동 세팅
* `asterisk/` : Asterisk 설정(pjsip, extensions, rtp 등)
* `recordings/` : MixMonitor WAV 저장 경로(폴더 유지, 파일은 보통 Git 제외)


