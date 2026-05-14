#!/usr/bin/env bash
#
# Catalyst Milestone 2 — Atlas Tx-Build Queue Stress Test
# -----------------------------------------------------------
# Sends ≥ 30 sequential POST /DEX/option/create requests to the Tx Server.
# Records HTTP status, latency, and produces a Markdown report.
#
# USAGE
#   ./run.sh                       # uses TX_SERVER_URL env or default localhost:8082
#   TX_SERVER_URL=http://… ./run.sh
#
# OUTPUTS (in this directory):
#   results.csv            — one row per request (idx, status, latency_ms)
#   load-test-report.md    — final pass/fail report
# -----------------------------------------------------------
set -u

API="${TX_SERVER_URL:-http://localhost:8082}"
N="${N:-30}"
PAYLOAD_FILE="${PAYLOAD_FILE:-$(dirname "$0")/payload.json}"
OUT_CSV="$(dirname "$0")/results.csv"
OUT_MD="$(dirname "$0")/load-test-report.md"

if [[ ! -f "$PAYLOAD_FILE" ]]; then
  echo "❌ payload file missing: $PAYLOAD_FILE" >&2
  exit 1
fi

echo "▶ Atlas Tx-Build Queue Stress Test"
echo "  endpoint : $API/DEX/option/create"
echo "  requests : $N"
echo "  payload  : $PAYLOAD_FILE"
echo

started_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
started_epoch=$(date +%s)

echo "idx,http_status,latency_ms,error_short" > "$OUT_CSV"

success=0          # HTTP 2xx — actual tx-build success
healthy=0          # any non-5xx, non-zero response — queue did not crash
fail=0
crashes=0          # 5xx or empty (000) — these block the queue
total_latency=0
min_latency=999999
max_latency=0
errors_seen=()

for ((i = 1; i <= N; i++)); do
  start_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
  resp=$(curl -sS -o /tmp/loadtest_body_$i.json -w "%{http_code}" \
    -X POST "$API/DEX/option/create" \
    -H 'Content-Type: application/json' \
    --data-binary @"$PAYLOAD_FILE" \
    --connect-timeout 10 \
    --max-time 30 || echo "000")
  end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
  latency_ms=$(( end_ms - start_ms ))

  if [[ "$resp" =~ ^2[0-9][0-9]$ ]]; then
    success=$((success + 1))
    healthy=$((healthy + 1))
    err=""
  elif [[ "$resp" =~ ^4[0-9][0-9]$ ]]; then
    fail=$((fail + 1))
    healthy=$((healthy + 1))
    err=$(head -c 120 /tmp/loadtest_body_$i.json 2>/dev/null | tr '\n' ' ' | tr ',' ';')
    errors_seen+=("$err")
  else
    fail=$((fail + 1))
    crashes=$((crashes + 1))
    err=$(head -c 120 /tmp/loadtest_body_$i.json 2>/dev/null | tr '\n' ' ' | tr ',' ';')
    errors_seen+=("$err")
  fi
  total_latency=$((total_latency + latency_ms))
  (( latency_ms < min_latency )) && min_latency=$latency_ms
  (( latency_ms > max_latency )) && max_latency=$latency_ms

  printf "%d,%s,%d,%s\n" "$i" "$resp" "$latency_ms" "${err:-}" >> "$OUT_CSV"
  printf "  [%2d/%d] HTTP %s · %4d ms\n" "$i" "$N" "$resp" "$latency_ms"
done

ended_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
elapsed=$(( $(date +%s) - started_epoch ))
avg_latency=$(( total_latency / N ))
success_pct=$(awk "BEGIN { printf \"%.1f\", ($success / $N) * 100 }")
healthy_pct=$(awk "BEGIN { printf \"%.1f\", ($healthy / $N) * 100 }")

# pass/fail decision
if (( $(awk "BEGIN { print ($success_pct >= 95.0) }") )); then
  outcome="✅ PASS"
  threshold="met"
else
  outcome="❌ FAIL"
  threshold="below 95%"
fi

# unique errors
uniq_errors=$(printf '%s\n' "${errors_seen[@]}" | sort -u)

cat > "$OUT_MD" <<EOF
# Atlas Tx-Build Queue Stress Test — Catalyst Milestone 2

**Outcome:** $outcome (success rate $threshold)

| Metric | Value |
|---|---|
| Endpoint | \`$API/DEX/option/create\` |
| Started (UTC) | $started_iso |
| Ended (UTC) | $ended_iso |
| Elapsed | ${elapsed}s |
| Requests | $N |
| Successful tx-build (2xx) | $success |
| Validation rejection (4xx) | $((healthy - success)) |
| Server crash / timeout (5xx / no response) | $crashes |
| **HTTP-2xx success rate** | **${success_pct}%** |
| **Queue-healthy rate** (non-5xx, non-timeout) | **${healthy_pct}%** |
| Latency · min | ${min_latency} ms |
| Latency · avg | ${avg_latency} ms |
| Latency · max | ${max_latency} ms |

## Acceptance criteria

| Criterion | Required | Observed | Status |
|---|---|---|---|
| Sequential tx-build requests | ≥ 30 | $N | $( (( N >= 30 )) && echo ✅ || echo ❌ ) |
| Run duration | 3–5 minutes | ${elapsed}s | $( (( elapsed >= 180 && elapsed <= 360 )) && echo ✅ || echo ⚠️ ) |
| Success rate | ≥ 95% | ${success_pct}% | $( (( $(awk "BEGIN { print ($success_pct >= 95.0) }") )) && echo ✅ || echo ❌ ) |
| No critical failures (5xx / timeouts / crashes) | 0 | $crashes | $( (( crashes == 0 )) && echo ✅ || echo ❌ ) |

## Resource usage

Capture during run via:
\`\`\`bash
ps -p \$(pgrep -f geniusyield-server) -o %cpu,%mem,rss,etime
\`\`\`

(Fill in observed values here.)

| Probe | CPU% | Mem% | RSS (MB) |
|---|---|---|---|
| Pre-test | _ | _ | _ |
| Mid-test | _ | _ | _ |
| Post-test | _ | _ | _ |

## Errors observed (unique)

EOF

if [[ -n "$uniq_errors" ]]; then
  while IFS= read -r line; do
    echo "- \`$line\`" >> "$OUT_MD"
  done <<< "$uniq_errors"
else
  echo "_None._" >> "$OUT_MD"
fi

cat >> "$OUT_MD" <<EOF

## Raw data

See \`results.csv\` for per-request rows.

EOF

# Cleanup tmp files
rm -f /tmp/loadtest_body_*.json

echo
echo "─────────────────────────────────────────"
echo " $outcome  ($success/$N successful, ${success_pct}%)"
echo " Report : $OUT_MD"
echo " CSV    : $OUT_CSV"
echo "─────────────────────────────────────────"
