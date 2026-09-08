#!/usr/bin/env bash

set -euo pipefail

INTAKE_URL="https://intake.sekoia.io/plain"
INTAKE_KEY="${INTAKE_KEY:-}"
HOST="http-server-krk01:443"

if [[ -z "$INTAKE_KEY" ]]; then
  read -r -s -p "Enter your Sekoia Intake Key: " INTAKE_KEY
  echo
fi

if [[ -z "$INTAKE_KEY" ]]; then
  echo "Error: intake key cannot be empty." >&2
  exit 1
fi

USERS=("bob" "alice" "tom" "lukas" "john" "gerald")
METHODS=("PUT" "GET")
PUT_STATUSES=(200 201 204)
GET_STATUSES=(200 304 404)
ENDPOINTS=("/api/data" "/api/users" "/api/config" "/api/events" "/dashboard" "/api/reports")
REFERRERS=("https://app.example.com/dashboard" "https://app.example.com/reports" "https://app.example.com/settings" "-")
USER_AGENTS=(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0 Safari/537.36"
  "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0"
)

trap 'echo; echo "Event sender stopped."; exit 0' INT TERM

random_element() {
  local arr=("$@")
  echo "${arr[RANDOM % ${#arr[@]}]}"
}

random_ip() {
  echo "$(( RANDOM % 223 + 1 )).$(( RANDOM % 256 )).$(( RANDOM % 256 )).$(( RANDOM % 254 + 1 ))"
}

echo "Starting HTTP access-log sender. Press Ctrl+C to stop."

while true; do
  CLIENT_IP=$(random_ip)
  USER=$(random_element "${USERS[@]}")
  METHOD=$(random_element "${METHODS[@]}")
  ENDPOINT=$(random_element "${ENDPOINTS[@]}")
  REFERRER=$(random_element "${REFERRERS[@]}")
  UA=$(random_element "${USER_AGENTS[@]}")
  TIMESTAMP=$(date +"%d/%b/%Y:%H:%M:%S %z")

  if [[ "$METHOD" == "PUT" ]]; then
    STATUS=$(random_element "${PUT_STATUSES[@]}")
  else
    STATUS=$(random_element "${GET_STATUSES[@]}")
  fi

  if [[ "$STATUS" == "204" || "$STATUS" == "304" ]]; then
    SIZE=0
  else
    SIZE=$(( RANDOM % 4096 + 256 ))
  fi

  LOG_LINE="${HOST} ${CLIENT_IP} - ${USER} [${TIMESTAMP}] \"${METHOD} ${ENDPOINT} HTTP/1.1\" ${STATUS} ${SIZE} \"${REFERRER}\" \"${UA}\""

  HTTP_RESPONSE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "$INTAKE_URL" \
    -H "X-SEKOIAIO-INTAKE-KEY: $INTAKE_KEY" \
    -H "Content-Type: text/plain" \
    --data "$LOG_LINE")

  printf "[%s] User: %-8s | IP: %-15s | Method: %-4s | Status: %s | HTTP: %s\n" \
    "$(date +"%H:%M:%S")" "$USER" "$CLIENT_IP" "$METHOD" "$STATUS" "$HTTP_RESPONSE"

  sleep $(( RANDOM % 31 + 15 ))
done
