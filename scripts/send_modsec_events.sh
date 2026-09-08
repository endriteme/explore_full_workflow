#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────
#  send_modsec_events.sh
#  Sends ModSecurity WAF events to Sekoia.io at random intervals
#  between 30 and 60 seconds, mimicking a real-time scenario.
# ─────────────────────────────────────────────────────────────

# ── Colours ──────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
DIM="\033[2m"

# ── Intake URL ────────────────────────────────────────────────
INTAKE_URL="https://intake.sekoia.io/plain"

# ── Event payloads (kept exactly as provided) ─────────────────
EVENT_1='[security2:error] [pid 11852:tid 4036848496] [client 192.168.1.100:35323] [client 192.168.1.100] ModSecurity: Warning. Pattern match "..." at ARGS:search. [file "/usr/apache/conf/waf/modsecurity_crs_sql_injection_attacks.conf"] [line "64"] [id "950001"] [rev "1"] [msg "SQL Injection Attack Detected"] [data "Matched Data: SELECT found within ARGS:search: SELECT * FROM users WHERE id=1 OR 1=1"] [severity "CRITICAL"] [ver "OWASP_CRS/3.3.0"] [hostname "apache-server.corp.local"] [uri "/search.php"] [unique_id "YkX2vlKC-YX738FovDc0GkwAAAAb"], referer: http://apache-server.corp.local/index.php'

EVENT_2='[security2:error] [pid 11852:tid 4036848496] [client 192.168.1.112:35323] [client 192.168.1.112] ModSecurity: Warning. Pattern match "..." at ARGS:search. [file "/usr/apache/conf/waf/modsecurity_crs_sql_injection_attacks.conf"] [line "64"] [id "950001"] [rev "1"] [msg "SQL Injection Attack Detected"] [data "Matched Data: SELECT found within ARGS:search: SELECT * FROM users WHERE id=1 OR 1=1"] [severity "CRITICAL"] [ver "OWASP_CRS/3.3.0"] [hostname "apache-server.corp.local"] [uri "/search.php"] [unique_id "YkX2vlKC-YX738FovDc0GkwAAAAb"], referer: http://apache-server.corp.local/index.php'

INTAKE_KEY="${INTAKE_KEY:-}"

if [[ -z "$INTAKE_KEY" ]]; then
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        Sekoia.io – ModSecurity Event Simulator           ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "${DIM}This script sends ModSecurity WAF events to Sekoia.io"
  echo -e "at random intervals between 30 and 60 seconds.${RESET}"
  echo ""
  read -r -s -p "$(echo -e ${YELLOW}"Enter your Sekoia.io Intake Key: "${RESET})" INTAKE_KEY
  echo ""
fi

if [[ -z "$INTAKE_KEY" ]]; then
  echo -e "${RED}✖  No intake key provided. Exiting.${RESET}"
  exit 1
fi

echo ""
echo -e "${GREEN}✔  Intake key accepted. Starting event loop…${RESET}"
echo -e "${DIM}   Press Ctrl+C at any time to stop.${RESET}"
echo ""

# ── Helper: format seconds as Xs or Xm Ys ────────────────────
format_delay() {
  local s=$1
  if (( s < 60 )); then
    echo "${s}s"
  else
    echo "$((s / 60))m $((s % 60))s"
  fi
}

# ── Event counter ─────────────────────────────────────────────
COUNT=0

# ── Main loop ────────────────────────────────────────────────
while true; do
  # Pick a random event (1 or 2)
  PICK=$(( (RANDOM % 2) + 1 ))

  if [[ "$PICK" -eq 1 ]]; then
    PAYLOAD="$EVENT_1"
    LABEL="Event #1  (client 192.168.1.100)"
  else
    PAYLOAD="$EVENT_2"
    LABEL="Event #2  (client 192.168.1.112)"
  fi

  # Send the event and keep the response body for troubleshooting
  RESPONSE_FILE=$(mktemp)
  HTTP_STATUS=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" \
    -X POST "$INTAKE_URL" \
    -H "X-SEKOIAIO-INTAKE-KEY: ${INTAKE_KEY}" \
    -H "Content-Type: text/plain" \
    --data-raw "$PAYLOAD")
  RESPONSE_BODY=$(cat "$RESPONSE_FILE")
  rm -f "$RESPONSE_FILE"

  COUNT=$(( COUNT + 1 ))
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  # Determine next delay before printing so we can show it immediately
  DELAY=$(( RANDOM % 31 + 30 ))   # 30–60 seconds
  NEXT_TIME=$(date -v "+${DELAY}S" '+%H:%M:%S' 2>/dev/null || date -d "+${DELAY} seconds" '+%H:%M:%S')
  DELAY_FMT=$(format_delay "$DELAY")

  # Status indicator
  if [[ "$HTTP_STATUS" == "200" ]] || [[ "$HTTP_STATUS" == "202" ]]; then
    STATUS_ICON="${GREEN}✔  Sent${RESET}"
  else
    STATUS_ICON="${RED}✖  HTTP ${HTTP_STATUS}${RESET}"
  fi

  echo -e "─────────────────────────────────────────────────────────"
  echo -e "  ${BOLD}[Event ${COUNT}]${RESET}  ${TIMESTAMP}"
  echo -e "  Payload  : ${CYAN}${LABEL}${RESET}"
  echo -e "  Status   : ${STATUS_ICON}"
  if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "202" ]]; then
    echo -e "  ${RED}Response : ${RESPONSE_BODY}${RESET}"
  fi
  echo -e "  Next in  : ${YELLOW}${DELAY_FMT}${RESET}  (at ${NEXT_TIME})"
  echo ""

  sleep "$DELAY"
done
