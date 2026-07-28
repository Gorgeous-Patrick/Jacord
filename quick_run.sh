#!/bin/bash
set -e

# One trial's worth of "load_channel" for jacord.  Called by
# sweep_prefetch_limit.sh once per (prefetch_limit, trial) with
# JAC_PROFILE_DIR / JAC_PROFILE_CSV / JAC_RESULTS_FILE already set.
#
# Assumes:
#   * MongoDB + Redis are already up.
#   * `jac_db.dump` is a mongodump archive of a seeded graph — restored
#     before each sweep to reset state without having to re-seed via API.

export base_url="localhost:8000"
export JAC_PROFILE_DIR=${JAC_PROFILE_DIR:-profiles}

TRIALS=${TRIALS:-40}
TEST_USER=${TEST_USER:-user_0000}
TEST_PASSWORD=${TEST_PASSWORD:-password}
WALKER=${WALKER:-load_channel}

echo "=== Restarting docker compose ==="
docker compose down
docker compose up -d
sleep 5

if [ -f jac_db.dump ]; then
    echo "=== Restoring MongoDB from dump ==="
    # -L follows the symlink if `jac_db.dump` is a link to dumps/<name>.dump;
    # without it, docker cp copies the link itself and mongorestore sees
    # a broken path inside the container.
    docker cp -L jac_db.dump mongodb:/tmp/jac_db.dump
    docker exec mongodb mongorestore --archive=/tmp/jac_db.dump --drop 2>&1 | tail -3
else
    echo "=== No jac_db.dump — using whatever's currently in MongoDB ==="
fi

echo "=== Clearing Redis ==="
docker exec redis redis-cli FLUSHALL || true

mkdir -p logs

echo "=== Stopping any running jac server ==="
pkill -f "jac start" 2>/dev/null || true
sleep 2

PREFETCH_LIMIT=$(grep 'prefetch_limit' jac.toml 2>/dev/null | sed 's/.*= *//' || echo "0")

# Ensure access_log is a per-trial CSV so hit-stats aggregation is clean.
if ! grep -q '^access_log' jac.toml; then
  sed -i '/^\[run\]/a access_log = ""' jac.toml
fi

echo "=== E2E Timing (${TRIALS} trials, server restarted each trial, prefetch_limit=$PREFETCH_LIMIT) ==="
echo ""

_tmpfile=$(mktemp)

for i in $(seq 1 "$TRIALS"); do
  TRIAL_DIR="$JAC_PROFILE_DIR/${WALKER}/trial_${i}"
  LOG_TRIAL="logs/jac_server_${WALKER}_limit${PREFETCH_LIMIT}_trial${i}.log"
  _profile_csv="$TRIAL_DIR/profile.csv"

  # Per-trial access_log path (sed-patch jac.toml — the [run] section read at startup).
  _access_log="logs/access_log_${WALKER}_limit${PREFETCH_LIMIT}_trial${i}.csv"
  rm -f "$_access_log"
  sed -i "s|^access_log = .*|access_log = \"$_access_log\"|" jac.toml

  docker exec redis redis-cli FLUSHALL > /dev/null 2>&1 || true

  mkdir -p "$TRIAL_DIR"
  JAC_PROFILE_DIR="$TRIAL_DIR" JAC_PROFILE_CSV="$_profile_csv" \
    JAC_DISABLE_GC=1 \
    jac start > "$LOG_TRIAL" 2>&1 &
  JAC_PID=$!

  # Wait for server ready.
  for _attempt in $(seq 1 60); do
    curl -sf "http://$base_url/docs" > /dev/null 2>&1 && break
    sleep 1
  done

  # Auth.
  token=$(curl -s -X POST "http://$base_url/user/login" \
    -H "Content-Type: application/json" \
    -d "{\"identity\":{\"type\":\"username\",\"value\":\"$TEST_USER\"},\"credential\":{\"type\":\"password\",\"password\":\"$TEST_PASSWORD\"}}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])")

  # Pick a random channel from the seeded set.
  channel_id=$(curl -s -X POST "http://$base_url/walker/ListChannelIds" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '{"limit": 100}' \
    | python3 -c "
import json, sys, random
reports = json.load(sys.stdin)['data'].get('reports') or []
ids = reports[0] if reports else []
print(random.choice(ids) if ids else '', end='')
")

  if [ -z "$channel_id" ]; then
    echo "  Trial $i: NO_CHANNEL_ID — did you bootstrap?"
    kill $JAC_PID 2>/dev/null || true
    pkill -f "jac start" 2>/dev/null || true
    sleep 2
    continue
  fi

  # New endpoint shape: spawn directly on the Channel anchor.  Empty
  # body — the anchor id lives in the URL path so TTG sees the walker
  # start on Channel (static edge-ref chain) instead of doing a jobj
  # lookup on Root.
  http_out=$(curl -s -w "%{http_code}\n%{time_total}" -o "$_tmpfile" -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "http://$base_url/walker/$WALKER/$channel_id")
  http_status=$(echo "$http_out" | head -1)
  e2e_time=$(echo "$http_out" | tail -1)
  resp_size=$(wc -c < "$_tmpfile")
  e2e_ms=$(awk "BEGIN {printf \"%.3f\", $e2e_time * 1000}")
  echo "  Trial $i: ${e2e_ms}ms  HTTP=$http_status  resp=${resp_size}bytes"

  # Breakdown from JAC_PROFILE_CSV.
  topo_idx_ms=""; ttg_ms=""; prefetch_ms=""; walker_ms=""
  if [ -f "$_profile_csv" ]; then
    last_row=$(tail -1 "$_profile_csv")
    topo_idx_ms=$(echo "$last_row" | awk -F',' '{print $6}')
    ttg_ms=$(echo "$last_row" | awk -F',' '{print $7}')
    prefetch_ms=$(echo "$last_row" | awk -F',' '{print $8}')
    walker_ms=$(echo "$last_row" | awk -F',' '{print $9}')
    echo "    breakdown: topo=${topo_idx_ms}ms ttg=${ttg_ms}ms prefetch=${prefetch_ms}ms walker=${walker_ms}ms"
  fi

  # Access-log tier summary.
  hit_rate=""; l1=""; l2=""; l3=""; miss=""
  if [ -s "$_access_log" ]; then
    read hit_rate l1 l2 l3 miss < <(python3 -c "
import csv
from collections import Counter
c = Counter()
with open('$_access_log') as f:
    for r in csv.DictReader(f):
        c[r['tier']] += 1
total = sum(c.values()) or 1
print(f\"{c['L1']*100/total:.1f} {c['L1']} {c['L2']} {c['L3']} {c['MISS']}\")
")
    echo "    hit rate: L1=${hit_rate}%  L1=${l1} L2=${l2} L3=${l3} MISS=${miss}"
  fi

  if [ -n "$JAC_RESULTS_FILE" ]; then
    echo "$WALKER,$PREFETCH_LIMIT,$i,$e2e_ms,$topo_idx_ms,$ttg_ms,$prefetch_ms,$walker_ms,$hit_rate,$l1,$l2,$l3,$miss" >> "$JAC_RESULTS_FILE"
  fi

  kill $JAC_PID 2>/dev/null || true
  pkill -f "jac start" 2>/dev/null || true
  sleep 2
done

sed -i 's|^access_log = .*|access_log = ""|' jac.toml
rm -f "$_tmpfile"

echo "=== Done ==="
