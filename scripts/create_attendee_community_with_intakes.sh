#!/usr/bin/env bash

set -euo pipefail

SEKOIA_API_BASE="${SEKOIA_API_BASE:-https://app.sekoia.io/api/v1}"
OUTPUT_FILE="${OUTPUT_FILE:-}"

ENTITY_NAME="Main infrastructure"
ENTITY_ID="main-infrastructure"
ENTITY_DESCRIPTION="Main infrastructure entity"
ALERTS_GENERATION_UUID="e54510b7-13dc-4773-ad0d-f8b13b9a939d"

INTAKE_NAME_1="Fortigate NGFW"
FORMAT_UUID_1="5702ae4e-7d8a-455f-a47b-ef64dd87c981"

INTAKE_NAME_2="Apache Web Server"
FORMAT_UUID_2="6c2a44e3-a86a-4d98-97a6-d575ffcb29f7"

INTAKE_NAME_3="Windows Server"
FORMAT_UUID_3="9281438c-f7c3-4001-9bcc-45fd108ba1be"

COMMUNITY_API_KEY="${COMMUNITY_API_KEY:-}"
INTAKE_API_KEY="${INTAKE_API_KEY:-}"
WORKSPACE_UUID="${WORKSPACE_UUID:-}"
ATTENDEE_LABEL="${ATTENDEE_LABEL:-XXX}"

if [[ -z "$COMMUNITY_API_KEY" ]]; then
  read -r -s -p "Enter the API key for community creation: " COMMUNITY_API_KEY
  echo
fi

if [[ -z "$WORKSPACE_UUID" ]]; then
  read -r -p "Enter the workspace UUID where the community will be created: " WORKSPACE_UUID
fi

if [[ -z "$INTAKE_API_KEY" ]]; then
  read -r -s -p "Enter the workspace-level API key for entity and intake creation: " INTAKE_API_KEY
  echo
fi

if [[ -z "$COMMUNITY_API_KEY" || -z "$WORKSPACE_UUID" || -z "$INTAKE_API_KEY" ]]; then
  echo "Error: community API key, workspace UUID, and intake API key are required." >&2
  exit 1
fi

CURRENT_DATE="$(date -u +%d-%m-%Y)"
COMMUNITY_NAME="${CURRENT_DATE}- Attendee ${ATTENDEE_LABEL} Community"
COMMUNITY_DESCRIPTION="${COMMUNITY_NAME}"

if [[ -n "$OUTPUT_FILE" ]]; then
  : > "$OUTPUT_FILE"
fi

echo "Creating community: ${COMMUNITY_NAME}..."

COMMUNITY_RESPONSE="$(
  jq -n \
    --arg name "$COMMUNITY_NAME" \
    --arg description "$COMMUNITY_DESCRIPTION" \
    '{name: $name, description: $description}' |
  curl --fail-with-body -sS -X POST \
    "${SEKOIA_API_BASE}/communities/${WORKSPACE_UUID}/sub-communities" \
    -H "Authorization: Bearer ${COMMUNITY_API_KEY}" \
    -H "Content-Type: application/json" \
    --data @-
)"

COMMUNITY_UUID="$(echo "$COMMUNITY_RESPONSE" | jq -er '.uuid')"
echo "Community created successfully: ${COMMUNITY_UUID}"

echo "Creating entity..."

ENTITY_RESPONSE="$(
  jq -n \
    --arg name "$ENTITY_NAME" \
    --arg entity_id "$ENTITY_ID" \
    --arg description "$ENTITY_DESCRIPTION" \
    --arg alerts_generation "$ALERTS_GENERATION_UUID" \
    --arg community_uuid "$COMMUNITY_UUID" \
    '{
      name: $name,
      entity_id: $entity_id,
      description: $description,
      alerts_generation: $alerts_generation,
      community_uuid: $community_uuid
    }' |
  curl --fail-with-body -sS -X POST \
    "${SEKOIA_API_BASE}/sic/conf/entities" \
    -H "Authorization: Bearer ${INTAKE_API_KEY}" \
    -H "Content-Type: application/json" \
    --data @-
)"

ENTITY_UUID="$(echo "$ENTITY_RESPONSE" | jq -er '.uuid')"
echo "Entity created successfully: ${ENTITY_UUID}"

create_intake() {
  local intake_name="$1"
  local format_uuid="$2"
  local output_variable="$3"

  echo "Creating intake: ${intake_name}..."

  INTAKE_RESPONSE="$(
    jq -n \
      --arg name "$intake_name" \
      --arg entity_uuid "$ENTITY_UUID" \
      --arg format_uuid "$format_uuid" \
      --arg community_uuid "$COMMUNITY_UUID" \
      '{
        name: $name,
        entity_uuid: $entity_uuid,
        format_uuid: $format_uuid,
        community_uuid: $community_uuid
      }' |
    curl --fail-with-body -sS -X POST \
      "${SEKOIA_API_BASE}/sic/conf/intakes" \
      -H "Authorization: Bearer ${INTAKE_API_KEY}" \
      -H "Content-Type: application/json" \
      --data @-
  )"

  local intake_uuid
  local intake_key
  local intake_configured
  intake_uuid="$(echo "$INTAKE_RESPONSE" | jq -er '.uuid')"

  echo "Configuring intake settings: ${intake_name}..."
  SETTINGS_RESPONSE_FILE=$(mktemp)
  SETTINGS_HTTP_STATUS=$(curl -sS -o "$SETTINGS_RESPONSE_FILE" -w "%{http_code}" -X PATCH \
    "${SEKOIA_API_BASE}/sic/conf/intakes/${intake_uuid}/settings" \
    -H "Authorization: Bearer ${INTAKE_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Content-Length: 0")

  if [[ "$SETTINGS_HTTP_STATUS" -lt 200 || "$SETTINGS_HTTP_STATUS" -ge 300 ]]; then
    echo "Error configuring intake settings: HTTP ${SETTINGS_HTTP_STATUS}" >&2
    cat "$SETTINGS_RESPONSE_FILE" >&2
    rm -f "$SETTINGS_RESPONSE_FILE"
    exit 1
  fi
  rm -f "$SETTINGS_RESPONSE_FILE"

  # Read the intake again after settings initialization. This retrieves the active key.
  INTAKE_RESPONSE="$(curl --fail-with-body -sS -X GET \
    "${SEKOIA_API_BASE}/sic/conf/intakes/${intake_uuid}" \
    -H "Authorization: Bearer ${INTAKE_API_KEY}" \
    -H "Accept: application/json")"

  intake_key="$(echo "$INTAKE_RESPONSE" | jq -er '.intake_key')"
  intake_configured="$(echo "$INTAKE_RESPONSE" | jq -er '.configured')"

  if [[ "$intake_configured" != "true" ]]; then
    echo "Error: intake settings were not configured for ${intake_name}." >&2
    exit 1
  fi

  printf -v "$output_variable" '%s' "$intake_key"
  echo "Intake created and configured successfully: ${intake_uuid}"

  if [[ -z "$OUTPUT_FILE" ]]; then
    echo "Intake key: ${intake_key}"
  fi
}

FORTIGATE_INTAKE_KEY=""
HTTP_INTAKE_KEY=""
WINDOWS_INTAKE_KEY=""

create_intake "$INTAKE_NAME_1" "$FORMAT_UUID_1" FORTIGATE_INTAKE_KEY
create_intake "$INTAKE_NAME_2" "$FORMAT_UUID_2" HTTP_INTAKE_KEY
create_intake "$INTAKE_NAME_3" "$FORMAT_UUID_3" WINDOWS_INTAKE_KEY

if [[ -n "$OUTPUT_FILE" ]]; then
  {
    printf 'COMMUNITY_UUID=%q\n' "$COMMUNITY_UUID"
    printf 'ENTITY_UUID=%q\n' "$ENTITY_UUID"
    printf 'COMMUNITY_NAME=%q\n' "$COMMUNITY_NAME"
    printf 'FORTIGATE_INTAKE_KEY=%q\n' "$FORTIGATE_INTAKE_KEY"
    printf 'HTTP_INTAKE_KEY=%q\n' "$HTTP_INTAKE_KEY"
    printf 'WINDOWS_INTAKE_KEY=%q\n' "$WINDOWS_INTAKE_KEY"
  } > "$OUTPUT_FILE"
  chmod 600 "$OUTPUT_FILE" 2>/dev/null || true
fi

unset COMMUNITY_API_KEY INTAKE_API_KEY

echo "Community, entity, and all three intakes were created successfully."
