#!/usr/bin/env bash

set -euo pipefail

INTAKE_KEY="${INTAKE_KEY:-}"
IOC_INPUT="${IOC_INPUT:-}"

if [[ -z "$INTAKE_KEY" ]]; then
  read -r -s -p "Enter your Sekoia.io Intake Key: " INTAKE_KEY
  echo
fi

if [[ -z "$IOC_INPUT" ]]; then
  read -r -p "Enter the IOC IP address to simulate traffic towards: " IOC_INPUT
fi

if [[ -z "$INTAKE_KEY" || -z "$IOC_INPUT" ]]; then
  echo "Error: intake key and IOC IP address are required." >&2
  exit 1
fi

echo "Starting FortiGate event sender. IOC target: ${IOC_INPUT}"
echo "Press Ctrl+C to stop."

rand_int() {
  local min=$1
  local max=$2
  echo $(( RANDOM % (max - min + 1) + min ))
}

random_internal_ip() {
  local class=$(( RANDOM % 3 ))
  case $class in
    0) echo "10.$(rand_int 0 255).$(rand_int 0 255).$(rand_int 1 254)" ;;
    1) echo "172.$(rand_int 16 31).$(rand_int 0 255).$(rand_int 1 254)" ;;
    2) echo "192.168.$(rand_int 0 255).$(rand_int 1 254)" ;;
  esac
}

random_external_ip() {
  while true; do
    local a=$(rand_int 1 223)
    local b=$(rand_int 0 255)
    local c=$(rand_int 0 255)
    local d=$(rand_int 1 254)
    if [[ $a -eq 10 ]]; then continue
    elif [[ $a -eq 127 ]]; then continue
    elif [[ $a -eq 169 && $b -eq 254 ]]; then continue
    elif [[ $a -eq 172 && $b -ge 16 && $b -le 31 ]]; then continue
    elif [[ $a -eq 192 && $b -eq 168 ]]; then continue
    elif [[ $a -eq 100 && $b -ge 64 && $b -le 127 ]]; then continue
    elif [[ $a -eq 198 && ($b -eq 18 || $b -eq 19) ]]; then continue
    fi
    echo "${a}.${b}.${c}.${d}"
    break
  done
}

IOC_INTERNAL_IPS=("192.168.1.100" "192.168.1.112")
IOC_EXTERNAL_IP="$IOC_INPUT"
PHASE1_DURATION=900
START_TIME=$(date -u +%s)
NEXT_IOC_TIME=$(( START_TIME + $(rand_int 30 120) ))

send_event() {
  local srcip=$1
  local dstip=$2
  local ts dt tm
  ts=$(date -u +%s)
  dt=$(date -u +"%Y-%m-%d")
  tm=$(date -u +"%H:%M:%S")

  RESPONSE_FILE=$(mktemp)
  HTTP_STATUS=$(curl -sS -o "$RESPONSE_FILE" -w "%{http_code}" -X POST https://intake.sekoia.io/plain \
    -H "X-SEKOIAIO-INTAKE-KEY: ${INTAKE_KEY}" \
    -H "Content-Type: text/plain" \
    -d "date=${dt} time=${tm} logid=\"0000000013\" type=\"traffic\" subtype=\"forward\" level=\"notice\" vd=\"root\" eventtime=${ts} srcip=${srcip} srcport=54321 srcintf=\"port2\" srcintfrole=\"lan\" dstip=${dstip} dstport=443 dstintf=\"port1\" dstintfrole=\"wan\" proto=6 action=\"accept\" policyid=1 service=\"HTTPS\" dstcountry=\"Germany\" srccountry=\"Reserved\" trandisp=\"snat\" transip=198.51.100.1 transport=54321 app=\"HTTPS\" appcat=\"Network.Service\" apprisk=\"low\" duration=12 sentbyte=512 rcvdbyte=256 sentpkt=8 rcvdpkt=5"
  )
  RESPONSE_BODY=$(cat "$RESPONSE_FILE")
  rm -f "$RESPONSE_FILE"
}

while true; do
  NOW=$(date -u +%s)
  ELAPSED=$(( NOW - START_TIME ))

  SRCIP=$(random_internal_ip)
  DSTIP=$(random_external_ip)
  send_event "$SRCIP" "$DSTIP"
  echo "[$(date -u +"%H:%M:%S")] Event sent, ${SRCIP} -> ${DSTIP} | HTTP ${HTTP_STATUS}"
  if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "202" ]]; then
    echo "Response body: ${RESPONSE_BODY}"
  fi

  if [[ $NOW -ge $NEXT_IOC_TIME ]]; then
    IOC_SRC="${IOC_INTERNAL_IPS[$(( RANDOM % 2 ))]}"
    send_event "$IOC_SRC" "$IOC_EXTERNAL_IP"
    echo "[$(date -u +"%H:%M:%S")] IOC sent, ${IOC_SRC} -> ${IOC_EXTERNAL_IP}"

    if [[ $ELAPSED -lt $PHASE1_DURATION ]]; then
      INTERVAL=$(rand_int 30 120)
    else
      INTERVAL=$(rand_int 600 800)
    fi

    NEXT_IOC_TIME=$(( NOW + INTERVAL ))
    echo "Next IOC event in ${INTERVAL}s"
  fi

  sleep 3
done
