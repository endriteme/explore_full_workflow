#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Sekoia Windows Event Log Simulator
# Sends random Windows logon events (4624/4625) to Sekoia every 10-30 seconds.
#
# Usage:
#   chmod +x sendwindowsdata.sh
#   ./sendwindowsdata.sh
# ─────────────────────────────────────────────────────────────────────────────

INTAKE_URL="https://intake.sekoia.io/plain"

INTAKE_KEY="${INTAKE_KEY:-}"

if [ -z "$INTAKE_KEY" ]; then
    echo ""
    echo "  Sekoia Windows Event Simulator"
    echo ""
    read -r -p "  Enter your Intake Key: " INTAKE_KEY_RAW
    echo ""
    INTAKE_KEY="${INTAKE_KEY_RAW}"
fi

# Strip any accidental leading/trailing whitespace
INTAKE_KEY=$(echo "${INTAKE_KEY}" | tr -d '[:space:]')

# Diagnostic only: this is a one-way fingerprint, not the intake key.
if command -v sha256sum >/dev/null 2>&1; then
    INTAKE_KEY_FINGERPRINT=$(printf '%s' "$INTAKE_KEY" | sha256sum | cut -c1-16)
else
    INTAKE_KEY_FINGERPRINT=$(printf '%s' "$INTAKE_KEY" | shasum -a 256 | cut -c1-16)
fi
echo "Intake key fingerprint: ${INTAKE_KEY_FINGERPRINT}"

if [ -z "$INTAKE_KEY" ]; then
    echo "  Error: Intake key cannot be empty. Exiting."
    exit 1
fi

SERVERS=("win-server-krk01" "win-server-krk02" "win-server-krk03")
USERS=("bob" "alice" "tom" "lukas")
WORKSTATIONS=("DESKTOP-FINANCE01" "DESKTOP-HR02" "LAPTOP-SALES03" "DESKTOP-IT04" "LAPTOP-MGMT05")
FAILURE_REASONS=("Unknown user name or bad password." "Account locked out." "Account disabled.")
SUB_STATUSES=("0xc000006a" "0xc0000064" "0xc0000072")

random_ip() {
    echo "$((RANDOM % 200 + 10)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 253 + 1))"
}

to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

echo "  Starting... Press Ctrl+C to stop."
echo ""

count=0

while true; do
    server="${SERVERS[$((RANDOM % 3))]}"
    user="${USERS[$((RANDOM % 4))]}"
    workstation="${WORKSTATIONS[$((RANDOM % 5))]}"
    ip=$(random_ip)
    port=$((RANDOM % 16383 + 49152))
    now=$(date '+%Y-%m-%d %H:%M:%S')
    server_upper=$(to_upper "$server")
    logon_type="3"
    [ $((RANDOM % 5)) -eq 0 ] && logon_type="10"

    if [ $((RANDOM % 100)) -lt 65 ]; then
        event_id=4624
        outcome="SUCCESS (4624)"
        logon_id="0x$(printf '%06x' $((RANDOM * 32 + RANDOM)))"
        extra_fields="\"TargetLogonId\":\"${logon_id}\",\"LogonGuid\":\"{00000000-0000-0000-0000-000000000000}\""
    else
        event_id=4625
        outcome="FAILURE (4625)"
        failure="${FAILURE_REASONS[$((RANDOM % 3))]}"
        substatus="${SUB_STATUSES[$((RANDOM % 3))]}"
        extra_fields="\"Status\":\"0xc000006d\",\"SubStatus\":\"${substatus}\",\"FailureReason\":\"${failure}\""
    fi

    payload="{\"EventTime\":\"${now}\",\"Hostname\":\"${server}\",\"EventID\":${event_id},\"SourceName\":\"Microsoft-Windows-Security-Auditing\",\"ProviderGuid\":\"{54849625-5478-4994-a5ba-3e3b0328c30d}\",\"Version\":0,\"Channel\":\"Security\",\"Computer\":\"${server}\",\"SubjectUserSid\":\"S-1-0-0\",\"SubjectUserName\":\"-\",\"SubjectDomainName\":\"-\",\"SubjectLogonId\":\"0x0\",\"TargetUserName\":\"${user}\",\"TargetDomainName\":\"${server_upper}\",\"LogonType\":\"${logon_type}\",\"LogonProcessName\":\"NtLmSsp\",\"AuthenticationPackageName\":\"NTLM\",\"WorkstationName\":\"${workstation}\",\"ProcessId\":\"0x0\",\"ProcessName\":\"-\",\"IpAddress\":\"${ip}\",\"IpPort\":\"${port}\",${extra_fields}}"

    # Use a temp file to capture response body and status separately
    tmp=$(mktemp)
    http_status=$(curl -s -o "${tmp}" -w "%{http_code}" -X POST "${INTAKE_URL}" \
        -H "X-SEKOIAIO-INTAKE-KEY: ${INTAKE_KEY}" \
        -H "Content-Type: text/plain" \
        --data-raw "${payload}")
    response_body=$(cat "${tmp}")
    rm -f "${tmp}"

    count=$((count + 1))
    printf "[%4d] %s  %-20s  user=%-6s  server=%s  src=%-16s  HTTP=%s\n" \
        "$count" "$now" "$outcome" "$user" "$server" "$ip" "$http_status"

    if [ "$http_status" != "200" ] && [ "$http_status" != "202" ]; then
        echo "       ⚠️  Error: ${response_body}"
    fi

    delay=$((RANDOM % 21 + 10))
    echo "       Next event in ${delay}s..."
    sleep "$delay"
done
