#!/usr/bin/env bash
# usage:
#    ./bin/argo cloud.monadical.com http://127.0.0.1:9089

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

DOMAIN="$1"                                         # e.g. "cloud.monadical.com"
URL="$2"                                            # e.g. "https://127.0.0.1:9089"

read SCHEME HOST PORT <<<$(IFS="://"; echo "$URL")

REFRESH=1;                                            # e.g. 1 second between checks
TIMEOUT=60;                                           # e.g. 5 seconds before a check is considered failing
ROOTDOMAIN=$(echo "$DOMAIN" | sed -r 's/.*\.([^.]+\.[^.]+)$/\1/')  # e.g. monadical.com

PID_FILE="$BASE_DIR/data/tmp/cloudflared.$DOMAIN.pid"
CERT_FILE="$BASE_DIR/data/certs/$ROOTDOMAIN.pem"

function log() {
    echo -e "$(date +"%Y-%m-%d %H:%M:%S") $*" > /dev/stderr
}

function onexit() {
    exitstatus=$?
    echo ""
    log "[X] Stopped Cloudflare Argo tunnel setup with exit status=$exitstatus."
    exit $exitstatus
}
trap onexit EXIT

if [[ ! "$DOMAIN" ]]; then
    log "[X] Missing a valid domain argument e.g. [domain.example.com]: '$*'.\nUsage:\n    $0 [domain.example.com] [127.0.0.1:8000]"
    exit 2
fi
if ! dig -4 +short "$ROOTDOMAIN" NS | grep -q '\.ns\.cloudflare\.com\.'; then
    log "[X] DNS for $ROOTDOMAIN NS did not resolve to *.ns.cloudflare.com"
    exit 2
fi
if [[ ! "$HOST" || ! "$PORT" || "$HOST" == "$PORT" ]]; then
    log "[X] Missing a valid host:port argument e.g. [127.0.0.1:8000]: '$*'.\nUsage:\n    $0 [domain.example.com] [127.0.0.1:8000]"
    exit 2
fi

log "[+] Setting up Cloudflare Argo tunnel $DOMAIN->$SCHEME://$HOST:$PORT..."

if [ ! -d "$BASE_DIR/data" ]; then
    log "[X] No argo config dir exists at $BASE_DIR (is this script placed the right folder?)."
    exit 2
fi

mkdir -p "$BASE_DIR/data/tmp"
if [ ! -f "$CERT_FILE" ]; then
    log "[X] Missing certificate at '$CERT_FILE'.\nTo generate it, run:\n    cloudflared tunnel login && cp ~/.cloudflared/cert.pem '$CERT_FILE'\n    or get it from https://dash.cloudflare.com/argotunnel"
    exit 2
fi

WAITED=0
while ! nc -z "$HOST" "$PORT"; do
    sleep $REFRESH
    if ((WAITED==0)); then
        log "[*] Waiting up to $TIMEOUT seconds for $HOST:$PORT to be available..."
    fi
    ((WAITED+=REFRESH)) && ((WAITED>=TIMEOUT)) && break
    echo -n "." > /dev/stderr
done

if ((WAITED!=0)); then
    echo ""
    if ((WAITED<TIMEOUT)); then
        log "[√] $HOST:$PORT is up after $WAITED seconds."
    else
        log "[!] $HOST:$PORT is still down, cloudflared may fail to start..."
    fi
fi

log "[*] Starting cloudflared process..."
exec "$BASE_DIR/bin/cloudflared" \
    tunnel \
    --url "$URL" \
    --hostname "$DOMAIN" \
    --origin-server-name "$ROOTDOMAIN" \
    --origincert "$CERT_FILE" \
    --pidfile "$PID_FILE" \
    --no-tls-verify
