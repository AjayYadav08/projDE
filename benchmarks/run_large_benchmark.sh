#!/usr/bin/env bash
# =====================================================================
# MakeMyTrip DBMS Project: Phase 5 Automated Large Scale Benchmark
# Automates the entire end-to-end execution on large_data/ when released.
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="${1:-makemytrip_large}"
DATA_DIR="$ROOT/large_data"
RUNS="${2:-3}"

echo "====================================================================="
echo "MakeMyTrip Phase 5: Large Scale Benchmark Runner (20x Scale)"
echo "Database Target: $DB"
echo "Data Directory:  $DATA_DIR"
echo "Benchmark Runs:  $RUNS"
echo "====================================================================="

if [[ ! -d "$DATA_DIR" ]]; then
  echo ""
  echo "⚠️  ERROR: Large data directory not found at: $DATA_DIR"
  echo "Faculty will release 'large_data.zip' by Thu 19 Nov 2026."
  echo "To run this benchmark:"
  echo "  1. Download large_data.zip and place it in the project root."
  echo "  2. Run: unzip large_data.zip"
  echo "  3. Re-execute: ./benchmarks/run_large_benchmark.sh"
  echo ""
  exit 1
fi

echo "[1/5] Initializing fresh database: $DB..."
dropdb --if-exists "$DB"
createdb "$DB"

echo "[2/5] Creating schema and constraints from sql/01_schema.sql..."
psql -d "$DB" -f "$ROOT/sql/01_schema.sql" -v ON_ERROR_STOP=1 > /dev/null

echo "[3/5] Loading large dataset (~2.9M bookings) via sql/03_load_large_data.sql..."
psql -d "$DB" -f "$ROOT/sql/03_load_large_data.sql" -v ON_ERROR_STOP=1

echo "[4/5] Applying production indexes from sql/05_indexes.sql..."
psql -d "$DB" -f "$ROOT/sql/05_indexes.sql" -v ON_ERROR_STOP=1 > /dev/null

echo "[5/5] Running benchmark harness with sql/06_optimized_queries.sql ($RUNS runs)..."
"$ROOT/benchmarks/run_benchmark.sh" "$DB" "large" "$RUNS" "$ROOT/sql/06_optimized_queries.sql"

echo ""
echo "✅ Large benchmark complete! Results saved to:"
echo "   - Summary: $ROOT/benchmarks/results/large/summary.csv"
echo "   - Raw Plans: $ROOT/benchmarks/results/large/*.txt"
echo "====================================================================="
