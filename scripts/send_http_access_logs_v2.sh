#!/bin/bash

# ──────────────────────────────────────────────
#  Sekoia.io – Random Log Event Sender
#  Sends fake Apache-style access log events to
#  the Sekoia plain intake endpoint.
# ──────────────────────────────────────────────

INTAKE_URL="https://intake.sekoia.io/plain"
HOST="http-server-krk01:443"

USERS=("bob" "alice" "tom" "lukas" "john" "gerald")
METHODS=("PUT" "GET")

# Top 3 realistic HTTP status codes per method
PUT_STATUSES=(200 201 204)
GET_STATUSES=(200 304 404)

ENDPOINTS=(
  "/api/data"
  "/api/users"
  "/api/config"
  "/api/events"
  "/dashboard"
  "/api/reports"
)

REFERRERS=(
  "https://app.example.com/dashboard"
  "https://app.example.com/reports"
  "https://app.example.com/settings"
  "-"
)

USER_AGENTS=(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0 Safari/537.36"
  "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0"
)

INTAKE_KEY="${INTAKE_KEY:-}"

if [[ -z "$INTAKE_KEY" ]]; then
  echo ""
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║   Sekoia.io – Random Event Sender        ║"
  echo "  ║   Press Ctrl+C to stop at any time       ║"
  echo "  ╚══════════════════════════════════════════╝"
  echo ""
  read -rsp "  Enter your Sekoia Intake Key: " INTAKE_KEY
  echo ""
  echo ""
fi

if [[ -z "$INTAKE_KEY" ]]; then
  echo "  [ERROR] No intake key provided. Exiting."
  exit 1
fi

# ── Graceful Ctrl+C handler ────────────────────
trap 'echo ""; echo "  [STOPPED] Event sender terminated. Goodbye!"; exit 0' INT

echo "  [STARTED] Sending random events every 15–45 seconds…"
echo ""

# ── Helper: pick a random array element ───────
random_element() {
  local arr=("$@")
  echo "${arr[RANDOM % ${#arr[@]}]}"
}

# ── Helper: generate a random public-looking IP ─
random_ip() {
  echo "$(( RANDOM % 223 + 1 )).$(( RANDOM % 256 )).$(( RANDOM % 256 )).$(( RANDOM % 254 + 1 ))"
}

# ── Main loop ─────────────────────────────────
while true; do
  # Random picks
  CLIENT_IP=$(random_ip)
  USER=$(random_element "${USERS[@]}")
  METHOD=$(random_element "${METHODS[@]}")
  ENDPOINT=$(random_element "${ENDPOINTS[@]}")
  REFERRER=$(random_element "${REFERRERS[@]}")
  UA=$(random_element "${USER_AGENTS[@]}")
  TIMESTAMP=$(date +"%d/%b/%Y:%H:%M:%S %z")

  # Status code depends on method
  if [[ "$METHOD" == "PUT" ]]; then
    STATUS=$(random_element "${PUT_STATUSES[@]}")
  else
    STATUS=$(random_element "${GET_STATUSES[@]}")
  fi

  # Fake response size (bytes) – 0 for 204/304, random otherwise
  if [[ "$STATUS" == "204" || "$STATUS" == "304" ]]; then
    SIZE=0
  else
    SIZE=$(( RANDOM % 4096 + 256 ))
  fi

  # Build the log line (Apache Combined Log Format)
  # Format: server_host  client_ip  ident  auth_user  [timestamp]  "request"  status  bytes  "referrer"  "user-agent"
  LOG_LINE="${HOST} ${CLIENT_IP} - ${USER} [${TIMESTAMP}] \"${METHOD} ${ENDPOINT} HTTP/1.1\" ${STATUS} ${SIZE} \"${REFERRER}\" \"${UA}\""

  # Send to Sekoia and keep the response body for troubleshooting
  RESPONSE_FILE=$(mktemp)
  HTTP_RESPONSE=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" \
    -X POST "$INTAKE_URL" \
    -H "X-SEKOIAIO-INTAKE-KEY: $INTAKE_KEY" \
    -H "Content-Type: text/plain" \
    --data "$LOG_LINE")
  RESPONSE_BODY=$(cat "$RESPONSE_FILE")
  rm -f "$RESPONSE_FILE"

  # Terminal feedback
  TIMESTAMP_SHORT=$(date +"%H:%M:%S")
  printf "  [%s] ✉  User: %-8s │ IP: %-15s │ Method: %-4s │ Status: %s │ Intake response: %s\n" \
    "$TIMESTAMP_SHORT" "$USER" "$CLIENT_IP" "$METHOD" "$STATUS" "$HTTP_RESPONSE"
  if [[ "$HTTP_RESPONSE" != "200" && "$HTTP_RESPONSE" != "202" ]]; then
    echo "  [ERROR BODY] ${RESPONSE_BODY}"
  fi

  # Wait a random interval between 15 and 45 seconds
  SLEEP_TIME=$(( RANDOM % 31 + 15 ))
  sleep "$SLEEP_TIME"
done
