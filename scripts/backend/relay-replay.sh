#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <message-id> [backend-base-url]"
  exit 1
fi

MESSAGE_ID="$1"
BACKEND_URL="${2:-http://localhost:3001}"

if [[ ! "$MESSAGE_ID" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "Invalid message id: $MESSAGE_ID"
  exit 1
fi

echo "Requesting relay retry for message $MESSAGE_ID via $BACKEND_URL"
curl -sS -X POST "${BACKEND_URL}/v1/relay/jobs/${MESSAGE_ID}/retry" \
  -H "Content-Type: application/json"
echo
