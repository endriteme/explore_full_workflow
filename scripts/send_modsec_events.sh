#!/usr/bin/env bash

set -euo pipefail

INTAKE_URL="https://intake.sekoia.io/plain"
INTAKE_KEY="${INTAKE_KEY:-}"

EVENT_1='[security2:error] [pid 11852:tid 4036848496] [client 192.168.1.100:35323] [client 192.168.1.100] ModSecurity: Warning. Pattern match "..." at ARGS:search. [file "/usr/apache/conf/waf/modsecurity_crs_sql_injection_attacks.conf"] [line "64"] [id "950001"] [rev "1"] [msg "SQL Injection Attack Detected"] [data "Matched Data: SELECT found within ARGS:search: SELECT * FROM users WHERE id=1 OR 1=1"] [severity "CRITICAL"] [ver "OWASP_CRS/3.3.0"] [hostname "apache-server.corp.local"] [uri "/search.php"] [unique_id "YkX2vlKC-YX738FovDc0GkwAAAAb"], referer: http://apache-server.corp.local/index.php'
EVENT_2='[security2:error] [pid 11852:tid 4036848496] [client 192.168.1.112:35323] [client 192.168.1.112] ModSecurity: Warning. Pattern match "..." at ARGS:search. [file "/usr/apache/conf/waf/modsecurity_crs_sql_injection_attacks.conf"] [line "64"] [id "950001"] [rev "1"] [msg "SQL Injection Attack Detected"] [data "Matched Data: SELECT found within ARGS:search: SELECT * FROM users WHERE id=1 OR 1=1"] [severity "CRITICAL"] [ver "OWASP_CRS/3.3.0"] [hostname "apache-server.corp.local"] [uri "/search.php"] [unique_id "YkX2vlKC-YX738FovDc0GkwAAAAb"], referer: http://apache-server.corp.local/index.php'

if [[ -z "$INTAKE_KEY" ]]; then
  read -r -s -p "Enter your Sekoia.io Intake Key: " INTAKE_KEY
  echo
fi

if [[ -z "$INTAKE_KEY" ]]; then
  echo "Error: intake key cannot be empty." >&2
  exit 1
fi

trap 'echo; echo "Event sender stopped."; exit 0' INT TERM

COUNT=0

echo "Starting ModSecurity event sender. Press Ctrl+C to stop."

while true; do
  PICK=$(( (RANDOM % 2) + 1 ))

  if [[ "$PICK" -eq 1 ]]; then
    PAYLOAD="$EVENT_1"
    LABEL="Event #1 (client 192.168.1.100)"
  else
    PAYLOAD="$EVENT_2"
    LABEL="Event #2 (client 192.168.1.112)"
  fi

  HTTP_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "$INTAKE_URL" \
    -H "X-SEKOIAIO-INTAKE-KEY: ${INTAKE_KEY}" \
    -H "Content-Type: text/plain" \
    --data-raw "$PAYLOAD")

  COUNT=$(( COUNT + 1 ))
  echo "[Event ${COUNT}] ${LABEL} | HTTP ${HTTP_STATUS}"

  sleep $(( RANDOM % 31 + 30 ))
done
