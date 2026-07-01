#!/bin/bash
set -e

# Configuration — SWEEP_PREFETCH_LIMITS (space-separated ints) can be
# overridden by env; standalone use picks up the defaults below.
if [ -n "$SWEEP_PREFETCH_LIMITS" ]; then
  read -ra PREFETCH_LIMITS <<< "$SWEEP_PREFETCH_LIMITS"
else
  PREFETCH_LIMITS=(0 500 1000 2000 3000 5000)
fi
RESULTS_FILE="sweep_prefetch_limit.csv"

# Clean all previous data
rm -rf logs profiles

echo "=== Jacord Prefetch Limit Sweep ==="
echo "Limits: ${PREFETCH_LIMITS[*]}"
echo ""

echo "walker,prefetch_limit,trial,e2e_ms,topo_idx_ms,ttg_ms,prefetch_ms,walker_ms,l1_hit_rate,l1,l2,l3,miss" > "$RESULTS_FILE"

for limit in "${PREFETCH_LIMITS[@]}"; do
  echo "========================================"
  echo "Testing: prefetch_limit=$limit"
  echo "========================================"

  # Patch prefetch_limit in jac.toml.
  if grep -q 'prefetch_limit' jac.toml 2>/dev/null; then
    sed -i "s/prefetch_limit = .*/prefetch_limit = $limit/" jac.toml
  fi

  # Toggle prefetching on/off at limit=0.
  if [ "$limit" -eq 0 ]; then
    sed -i 's/prefetching = .*/prefetching = "none"/' jac.toml 2>/dev/null || true
  else
    sed -i 's/prefetching = .*/prefetching = "ttg"/' jac.toml 2>/dev/null || true
  fi

  JAC_PROFILE_DIR="profiles/limit_${limit}" \
    JAC_RESULTS_FILE="$RESULTS_FILE" bash quick_run.sh
done

# Restore.
sed -i 's/prefetching = .*/prefetching = "ttg"/' jac.toml 2>/dev/null || true
sed -i "s/prefetch_limit = .*/prefetch_limit = 5000/" jac.toml 2>/dev/null || true

echo ""
echo "========================================"
echo "Sweep complete!"
echo "Results saved to: $RESULTS_FILE"
echo "========================================"
cat "$RESULTS_FILE"
