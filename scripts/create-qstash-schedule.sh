#!/usr/bin/env bash
# Creates the QStash schedule that calls /internal/poll every 2 minutes (720 msgs/day,
# under the 1,000/day free tier). Run once after the Render service is live.
# Usage: QSTASH_TOKEN=... API_URL=https://dailylah-api.onrender.com ./scripts/create-qstash-schedule.sh
set -euo pipefail
: "${QSTASH_TOKEN:?set QSTASH_TOKEN}"
: "${API_URL:?set API_URL}"
curl -sS -X POST "https://qstash.upstash.io/v2/schedules/${API_URL}/internal/poll" \
  -H "Authorization: Bearer ${QSTASH_TOKEN}" \
  -H "Upstash-Cron: */2 * * * *" \
  -H "Upstash-Method: POST"
echo
