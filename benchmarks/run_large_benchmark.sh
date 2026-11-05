#!/usr/bin/env bash
# =====================================================================
# MakeMyTrip DBMS Project: Phase 5 Automated Large Scale Benchmark
# Automates the entire end-to-end execution on large_data/ when released.
# Supports --validate for dry-run verification and --test for smoke tests.
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="run"
DB="${1:-makemytrip_large}"
RUNS="${2:-3}"
DATA_DIR="${3:-$ROOT/large_data}"

# Handle flags
if [[ "${1:-}" == "--validate" || "${1:-}" == "-v" ]]; then
  MODE="validate"
elif [[ "${1:-}" == "--test" || "${1:-}" == "-t" ]]; then
  MODE="test"
  DB="makemytrip_test_pipeline"
  RUNS=1
  DATA_DIR="$ROOT/seed_data"
fi

echo "====================================================================="
echo "MakeMyTrip Phase 5: Large Scale Benchmark Harness (PostgreSQL 16)"
echo "Mode:            $MODE"
echo "Target Database: $DB"
echo "Data Directory:  $DATA_DIR"
echo "Runs per Query:  $RUNS"
echo "====================================================================="

# Validate essential tools
if ! command -v psql >/dev/null 2>&1; then
  echo "❌ ERROR: 'psql' client not found in PATH."
  exit 1
fi

if ! command -v createdb >/dev/null 2>&1 || ! command -v dropdb >/dev/null 2>&1; then
  echo "❌ ERROR: 'createdb' or 'dropdb' not found in PATH."
  exit 1
fi

# Verify PostgreSQL server connectivity
if ! pg_isready -q; then
  echo "❌ ERROR: PostgreSQL server is not accepting connections."
  exit 1
fi

# Verify required project scripts
for req_file in "sql/01_schema.sql" "sql/03_load_large_data.sql" "sql/05_indexes.sql" "sql/06_optimized_queries.sql" "benchmarks/run_benchmark.sh"; do
  if [[ ! -f "$ROOT/$req_file" ]]; then
    echo "❌ ERROR: Required project file missing: $req_file"
    exit 1
  fi
done

if [[ ! -x "$ROOT/benchmarks/run_benchmark.sh" ]]; then
  chmod +x "$ROOT/benchmarks/run_benchmark.sh"
fi

# ---------------------------------------------------------------------
# MODE: VALIDATE (Dry-run check without requiring large_data on disk)
# ---------------------------------------------------------------------
if [[ "$MODE" == "validate" ]]; then
  echo "✔ PostgreSQL server is active and accessible."
  echo "✔ Database tools (psql, createdb, dropdb) verified."
  echo "✔ Schema file sql/01_schema.sql verified."
  echo "✔ Ingestion file sql/03_load_large_data.sql verified."
  echo "✔ Index file sql/05_indexes.sql verified."
  echo "✔ Workload file sql/06_optimized_queries.sql verified."
  echo "✔ Runner harness benchmarks/run_benchmark.sh verified."
  
  if [[ -d "$ROOT/large_data" ]]; then
    echo "✔ Large data directory large_data/ is PRESENT."
  else
    echo "ℹ Note: large_data/ is currently NOT present on disk."
    echo "  (Faculty will release large_data.zip by Thu 19 Nov 2026)."
  fi
  echo ""
  echo "✅ Validation successful: Harness environment and scripts are verified."
  exit 0
fi

# ---------------------------------------------------------------------
# MODE: TEST (Smoke test pipeline on test DB using seed data)
# ---------------------------------------------------------------------
if [[ "$MODE" == "test" ]]; then
  echo "Running end-to-end smoke test on test database: $DB..."
  
  if [[ ! -d "$DATA_DIR" ]]; then
    echo "❌ ERROR: Test data directory not found at $DATA_DIR"
    exit 1
  fi

  echo "[1/5] Initializing test database: $DB..."
  dropdb --if-exists "$DB"
  createdb "$DB"

  echo "[2/5] Creating schema and constraints..."
  psql -d "$DB" -f "$ROOT/sql/01_schema.sql" -v ON_ERROR_STOP=1 > /dev/null

  echo "[3/5] Loading test dataset via sql/02_load_data.sql..."
  psql -d "$DB" -f "$ROOT/sql/02_load_data.sql" -v ON_ERROR_STOP=1 > /dev/null

  echo "[4/5] Applying production indexes..."
  psql -d "$DB" -f "$ROOT/sql/05_indexes.sql" -v ON_ERROR_STOP=1 > /dev/null

  echo "[5/5] Running benchmark harness for 2 sample queries..."
  # Create a temporary workload with R01 and R06 to test runner execution
  TEST_WL="$(mktemp)"
  awk '/^-- @R01$/,/^-- @R02$/' "$ROOT/sql/06_optimized_queries.sql" | grep -v '^-- @R02$' > "$TEST_WL"
  awk '/^-- @R06$/,/^-- @R07$/' "$ROOT/sql/06_optimized_queries.sql" | grep -v '^-- @R07$' >> "$TEST_WL"
  
  "$ROOT/benchmarks/run_benchmark.sh" "$DB" "test_pipeline" 1 "$TEST_WL"
  rm -f "$TEST_WL"
  
  echo "Cleaning up temporary test database..."
  dropdb "$DB"
  rm -rf "$ROOT/benchmarks/results/test_pipeline"

  echo ""
  echo "✅ End-to-end benchmark harness test completed successfully!"
  echo "   All 5 pipeline steps (drop/create, schema, load, indexes, benchmark) passed."
  exit 0
fi

# ---------------------------------------------------------------------
# MODE: RUN (Real execution on large_data)
# ---------------------------------------------------------------------
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
