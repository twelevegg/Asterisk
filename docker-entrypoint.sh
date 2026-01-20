#!/bin/sh
set -eu

TEMPLATE=/etc/asterisk/pjsip.conf.tmpl
TARGET=/etc/asterisk/pjsip.conf

if [ ! -f "$TEMPLATE" ]; then
  echo "[entrypoint] Missing template: $TEMPLATE" >&2
  exit 1
fi

# ADVERTISE_ADDR
# - Prefer user-provided value via .env / environment
# - If empty, try to guess the outgoing interface IPv4 (ok for simple local tests)
if [ -z "${ADVERTISE_ADDR:-}" ]; then
  ADVERTISE_ADDR="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
  echo "[entrypoint] ADVERTISE_ADDR not set; guessed: $ADVERTISE_ADDR" >&2
else
  echo "[entrypoint] ADVERTISE_ADDR: $ADVERTISE_ADDR" >&2
fi

# LOCAL_NETS
# Comma-separated CIDRs considered "local" for NAT decisions.
# IMPORTANT (Windows Docker Desktop): do NOT include Docker ranges like 172.16.0.0/12.
# If included, Asterisk may advertise container IP (e.g. 172.19.0.2) in SDP => no audio.
if [ -z "${LOCAL_NETS:-}" ]; then
  LOCAL_NETS="192.168.0.0/16,10.0.0.0/8,100.64.0.0/10"
  echo "[entrypoint] LOCAL_NETS not set; default: $LOCAL_NETS" >&2
else
  echo "[entrypoint] LOCAL_NETS: $LOCAL_NETS" >&2
fi

# Render template (use sed to avoid external dependencies)
sed -e "s|__ADVERTISE_ADDR__|${ADVERTISE_ADDR}|g" \
    -e "s|__LOCAL_NETS__|${LOCAL_NETS}|g" \
    "$TEMPLATE" > "$TARGET"

# Ensure directories
mkdir -p /recordings
mkdir -p /var/log/asterisk/cdr-csv || true
chown -R asterisk:asterisk /var/log/asterisk 2>/dev/null || true

exec "$@"
