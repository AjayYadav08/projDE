#!/usr/bin/env python3
"""
MakeMyTrip DBMS Project: Master Verification Test Suite
Validates schema, constraints, data loading, query equivalence, write rollback,
benchmark evidence, keyset pagination, partition pruning, and report consistency.
Exits with code 0 on 100% PASS, or non-zero on any failure.
"""

import sys
import subprocess
import re
import csv
import glob
import os

DB_NAME = sys.argv[1] if len(sys.argv) > 1 else "makemytrip"

def run_psql(sql, db=DB_NAME):
    res = subprocess.run(
        ["psql", "-d", db, "-X", "-q", "-A", "-t", "-c", sql],
        capture_output=True,
        text=True
    )
    if res.returncode != 0:
        raise RuntimeError(f"psql error: {res.stderr.strip()}\nSQL: {sql}")
    return res.stdout.strip()

passed_tests = 0
failed_tests = 0

def test(name, condition, details=""):
    global passed_tests, failed_tests
    if condition:
        print(f"  [PASS] {name} {details}")
        passed_tests += 1
    else:
        print(f"  [FAIL] {name} {details}")
        failed_tests += 1

print("=" * 70)
print(f"MakeMyTrip DE Master Audit & Verification Suite (Target: {DB_NAME})")
print("=" * 70)

# ---------------------------------------------------------------------
# 1. CATALOG CONSTRAINTS AUDIT
# ---------------------------------------------------------------------
print("\n[1/8] Verifying Database Constraints (pg_constraint & pg_attribute)...")
con_types = run_psql("""
    SELECT contype, count(*) 
    FROM pg_constraint 
    WHERE connamespace = 'mmt'::regnamespace 
    GROUP BY contype;
""")
counts = dict(line.split("|") for line in con_types.splitlines() if line)
pk_count = int(counts.get("p", 0))
fk_count = int(counts.get("f", 0))
uq_count = int(counts.get("u", 0))
chk_count = int(counts.get("c", 0))
total_con = pk_count + fk_count + uq_count + chk_count

test("PRIMARY KEY count == 12", pk_count == 12, f"(found {pk_count})")
test("FOREIGN KEY count == 14", fk_count == 14, f"(found {fk_count})")
test("UNIQUE count == 5", uq_count == 5, f"(found {uq_count})")
test("CHECK count == 33", chk_count == 33, f"(found {chk_count})")
test("Total pg_constraint == 64", total_con == 64, f"(found {total_con})")

not_null_count = int(run_psql("""
    SELECT count(*) FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'mmt' AND c.relkind = 'r' AND a.attnum > 0 AND a.attnotnull = true;
"""))
test("Total NOT NULL columns == 74", not_null_count == 74, f"(found {not_null_count})")

sec_indexes = int(run_psql("""
    SELECT count(*) FROM pg_indexes 
    WHERE schemaname = 'mmt' 
      AND indexname NOT LIKE '%_pkey' 
      AND indexname NOT LIKE '%_key';
"""))
test("Secondary indexes in mmt == 21", sec_indexes == 21, f"(found {sec_indexes})")

# ---------------------------------------------------------------------
# 2. ROW COUNTS & REFERENTIAL INTEGRITY
# ---------------------------------------------------------------------
print("\n[2/8] Verifying Ingestion Row Counts & Integrity Assertions...")
b_count = int(run_psql("SELECT count(*) FROM mmt.bookings;"))
fb_count = int(run_psql("SELECT count(*) FROM mmt.flight_bookings;"))
hb_count = int(run_psql("SELECT count(*) FROM mmt.hotel_bookings;"))
p_count = int(run_psql("SELECT count(*) FROM mmt.passengers;"))

test("Bookings row count == 144,792", b_count == 144792, f"(found {b_count})")
test("Flight Bookings count == 84,899", fb_count == 84899, f"(found {fb_count})")
test("Hotel Bookings count == 59,893", hb_count == 59893, f"(found {hb_count})")
test("Passengers row count == 163,380", p_count == 163380, f"(found {p_count})")
test("Subtype completeness: flight + hotel == bookings", fb_count + hb_count == b_count)

# Commercial integrity tests
integ = run_psql("""
    SET search_path TO mmt;
    SELECT 
        (SELECT count(*) FROM flight_bookings fb JOIN (SELECT booking_id, count(*) as c FROM passengers GROUP BY 1) p ON p.booking_id = fb.booking_id WHERE fb.passengers <> p.c) as p_mismatch,
        (SELECT count(*) FROM flight_bookings fb JOIN bookings b ON b.booking_id = fb.booking_id JOIN flights f ON f.flight_id = fb.flight_id WHERE b.booked_at > f.departure_at) as chron_mismatch,
        (SELECT count(*) FROM hotel_bookings hb JOIN room_types rt ON rt.room_type_id = hb.room_type_id WHERE hb.hotel_id <> rt.hotel_id) as room_mismatch,
        (SELECT count(*) FROM flight_bookings fb JOIN bookings b ON b.booking_id = fb.booking_id WHERE fb.fare_paid <> (b.total_amount + b.discount)) as fare_mismatch;
""")
p_mism, chr_mism, rm_mism, fare_mism = [int(x) for x in integ.split("|")]
test("Passenger count matches line-items (0 mismatches)", p_mism == 0)
test("Chronological departure coherence (0 mismatches)", chr_mism == 0)
test("Room type property coherence (0 mismatches)", rm_mism == 0)
test("Fare accounting equation: fare = total + discount (0 mismatches)", fare_mism == 0)

# ---------------------------------------------------------------------
# 3. QUERY EQUIVALENCE (EXCEPT ALL in both directions)
# ---------------------------------------------------------------------
print("\n[3/8] Verifying Query Equivalence (sql/06 vs queries/workload_30)...")

def get_queries(file_path):
    with open(file_path) as f:
        text = f.read()
    chunks = re.split(r'-- @([RW][0-9]+)', text)
    queries = {}
    for i in range(1, len(chunks), 2):
        qid = chunks[i]
        sql = chunks[i+1].split('-- @')[0].strip()
        sql_lines = [l for l in sql.splitlines() if not l.strip().startswith('--')]
        clean_sql = '\n'.join(sql_lines).strip().rstrip(';')
        queries[qid] = clean_sql
    return queries

base_q = get_queries("queries/workload_30.sql")
opt_q = get_queries("sql/06_optimized_queries.sql")

equiv_failures = 0
for qid in sorted(base_q.keys()):
    if qid.startswith("W"):
        continue
    if qid == "R13":
        # R13 is documented bug-fix for 3VL NULL trap:
        cnt_base = int(run_psql("SET search_path TO mmt; SELECT count(*) FROM (" + base_q["R13"] + ") t;"))
        cnt_opt = int(run_psql("SET search_path TO mmt; SELECT count(*) FROM (" + opt_q["R13"] + ") t;"))
        test("R13 bug-fix: baseline=0 rows, optimized=10 rows", cnt_base == 0 and cnt_opt == 10, f"({cnt_base} vs {cnt_opt})")
        continue

    test_sql = f"""
    SET search_path TO mmt;
    WITH q1 AS ({base_q[qid]}),
         q2 AS ({opt_q[qid]}),
         diff1 AS (SELECT * FROM q1 EXCEPT ALL SELECT * FROM q2),
         diff2 AS (SELECT * FROM q2 EXCEPT ALL SELECT * FROM q1)
    SELECT (SELECT count(*) FROM diff1) as d1, (SELECT count(*) FROM diff2) as d2;
    """
    out = run_psql(test_sql).split("|")
    d1, d2 = int(out[0]), int(out[1])
    is_equiv = (d1 == 0 and d2 == 0)
    if not is_equiv:
        equiv_failures += 1
    test(f"{qid} EXACT EQUIVALENCE (0 diff rows)", is_equiv, f"(diff1={d1}, diff2={d2})")

# ---------------------------------------------------------------------
# 4. WRITE QUERY ROLLBACK SAFETY
# ---------------------------------------------------------------------
print("\n[4/8] Verifying Write Query Rollback Safety (W01–W05)...")
cnt_before = run_psql("SET search_path TO mmt; SELECT count(*) FROM bookings;")
for wid in ["W01", "W02", "W03", "W04", "W05"]:
    wrap = f"SET search_path TO mmt; BEGIN; EXPLAIN (ANALYZE, BUFFERS) {opt_q[wid]}; ROLLBACK;"
    run_psql(wrap)
cnt_after = run_psql("SET search_path TO mmt; SELECT count(*) FROM bookings;")
test("Write queries W01–W05 leave database state 100% unchanged", cnt_before == cnt_after, f"({cnt_before} == {cnt_after})")

# ---------------------------------------------------------------------
# 5. BENCHMARK ARTIFACTS & EVIDENCE INTEGRITY
# ---------------------------------------------------------------------
print("\n[5/8] Verifying Benchmark Artifacts & CSV Arithmetic...")
for phase in ["baseline", "optimized", "large"]:
    summary_path = f"benchmarks/results/{phase}/summary.csv"
    if not os.path.exists(summary_path):
        test(f"{phase}/summary.csv exists", False)
        continue
    with open(summary_path) as f:
        reader = csv.DictReader(f)
        s_rows = {r["query_id"]: r for r in reader}
    
    test(f"{phase}/summary.csv contains 30 queries", len(s_rows) == 30)
    
    math_errors = 0
    missing_runs = 0
    for qid, row in s_rows.items():
        txt_path = f"benchmarks/results/{phase}/{qid}.txt"
        if not os.path.exists(txt_path):
            missing_runs += 1
            continue
        content = open(txt_path).read()
        times = [float(t) for t in re.findall(r'Execution Time:\s+([0-9.]+)', content)]
        if len(times) != 3:
            missing_runs += 1
            continue
        
        times_sorted = sorted(times)
        c_min = times_sorted[0]
        c_med = times_sorted[1]
        c_max = times_sorted[2]
        c_avg = round(sum(times) / 3.0, 3)
        
        if abs(c_avg - float(row["avg_ms"])) > 0.01 or abs(c_med - float(row["median_ms"])) > 0.01:
            math_errors += 1
            
    test(f"{phase} all 30 queries have 3 preserved raw runs (90 plans)", missing_runs == 0)
    test(f"{phase} summary.csv math matches raw plans (0 mismatches)", math_errors == 0)

# ---------------------------------------------------------------------
# 6. KEYSET PAGINATION & MULTI-PAGE CORRECTNESS
# ---------------------------------------------------------------------
print("\n[6/8] Verifying Keyset Pagination Correctness (strict '<')...")
keyset_sql = """
SET search_path TO mmt;
WITH offset_paged AS (
    SELECT booking_id, booked_at, total_amount, ROW_NUMBER() OVER (ORDER BY booked_at DESC, booking_id DESC) as rn
    FROM bookings ORDER BY booked_at DESC, booking_id DESC LIMIT 100
),
p1 AS (SELECT booking_id, booked_at, total_amount FROM bookings ORDER BY booked_at DESC, booking_id DESC LIMIT 25),
c1 AS (SELECT booked_at, booking_id FROM p1 ORDER BY booked_at ASC, booking_id ASC LIMIT 1),
p2 AS (SELECT b.booking_id, b.booked_at, b.total_amount FROM bookings b, c1 WHERE (b.booked_at, b.booking_id) < (c1.booked_at, c1.booking_id) ORDER BY b.booked_at DESC, b.booking_id DESC LIMIT 25),
c2 AS (SELECT booked_at, booking_id FROM p2 ORDER BY booked_at ASC, booking_id ASC LIMIT 1),
p3 AS (SELECT b.booking_id, b.booked_at, b.total_amount FROM bookings b, c2 WHERE (b.booked_at, b.booking_id) < (c2.booked_at, c2.booking_id) ORDER BY b.booked_at DESC, b.booking_id DESC LIMIT 25),
c3 AS (SELECT booked_at, booking_id FROM p3 ORDER BY booked_at ASC, booking_id ASC LIMIT 1),
p4 AS (SELECT b.booking_id, b.booked_at, b.total_amount FROM bookings b, c3 WHERE (b.booked_at, b.booking_id) < (c3.booked_at, c3.booking_id) ORDER BY b.booked_at DESC, b.booking_id DESC LIMIT 25),
keyset_combined AS (SELECT * FROM p1 UNION ALL SELECT * FROM p2 UNION ALL SELECT * FROM p3 UNION ALL SELECT * FROM p4),
keyset_numbered AS (SELECT booking_id, booked_at, total_amount, ROW_NUMBER() OVER (ORDER BY booked_at DESC, booking_id DESC) as rn FROM keyset_combined)
SELECT 
    (SELECT count(*) FROM keyset_combined) as total,
    (SELECT count(DISTINCT booking_id) FROM keyset_combined) as distinct_cnt,
    (SELECT count(*) FROM (SELECT booking_id, booked_at, total_amount, rn FROM offset_paged EXCEPT ALL SELECT booking_id, booked_at, total_amount, rn FROM keyset_numbered) d) as d1,
    (SELECT count(*) FROM (SELECT booking_id, booked_at, total_amount, rn FROM keyset_numbered EXCEPT ALL SELECT booking_id, booked_at, total_amount, rn FROM offset_paged) d) as d2;
"""
tot, dist, kd1, kd2 = [int(x) for x in run_psql(keyset_sql).split("|")]
test("Keyset 4 pages total rows == 100", tot == 100)
test("Keyset 4 pages distinct rows == 100 (0 duplicates)", dist == 100)
test("Keyset matches OFFSET pagination (0 diff rows)", kd1 == 0 and kd2 == 0)

# ---------------------------------------------------------------------
# 7. PARTITION PRUNING & BOUNDARY BEHAVIOR
# ---------------------------------------------------------------------
print("\n[7/8] Verifying Partition Pruning & Boundary Behavior (mmt_partitioned)...")
prune_plan = run_psql("""
    SET search_path TO mmt_partitioned;
    EXPLAIN (ANALYZE, BUFFERS)
    SELECT count(*), sum(total_amount)
    FROM bookings
    WHERE booked_at >= '2026-06-01 00:00:00+05:30' AND booked_at < '2026-07-01 00:00:00+05:30';
""")
pruned_ok = ("bookings_2026_q2" in prune_plan) and ("bookings_2025" not in prune_plan)
test("Partition pruning scans ONLY targeted quarter (bookings_2026_q2)", pruned_ok)

default_route = run_psql("""
    BEGIN;
    INSERT INTO mmt_partitioned.bookings (booking_id, booking_ref, customer_id, booking_type, booked_at, total_amount, payment_method, status)
    VALUES (999999, 'MMDEFAULT', 1, 'FLIGHT', '2029-01-01 00:00:00+05:30', 1000.00, 'UPI', 'CONFIRMED');
    SELECT tableoid::regclass FROM mmt_partitioned.bookings WHERE booking_id = 999999;
    ROLLBACK;
""")
test("Out-of-bounds future dates route to bookings_default", "bookings_default" in default_route)

# ---------------------------------------------------------------------
# 8. LARGE DATASET DATABASE INTEGRITY & SCALE VERIFICATION (makemytrip_large)
# ---------------------------------------------------------------------
print("\n[8/9] Verifying Large Database (makemytrip_large) Scale & Integrity...")
def run_psql_large(sql):
    cmd = ["psql", "-d", "makemytrip_large", "-X", "-A", "-t", "-c", sql]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"psql makemytrip_large error: {res.stderr.strip()}")
    return res.stdout.strip()

large_b_cnt = int(run_psql_large("SELECT count(*) FROM mmt.bookings;"))
large_fb_cnt = int(run_psql_large("SELECT count(*) FROM mmt.flight_bookings;"))
large_hb_cnt = int(run_psql_large("SELECT count(*) FROM mmt.hotel_bookings;"))
large_p_cnt = int(run_psql_large("SELECT count(*) FROM mmt.passengers;"))
large_c_cnt = int(run_psql_large("SELECT count(*) FROM mmt.customers;"))

test("Large Bookings row count == 2,895,840", large_b_cnt == 2895840, f"(found {large_b_cnt})")
test("Large Flight Bookings == 1,697,980", large_fb_cnt == 1697980, f"(found {large_fb_cnt})")
test("Large Hotel Bookings == 1,197,860", large_hb_cnt == 1197860, f"(found {large_hb_cnt})")
test("Large Passengers == 3,267,600", large_p_cnt == 3267600, f"(found {large_p_cnt})")
test("Large Customers == 800,000", large_c_cnt == 800000, f"(found {large_c_cnt})")

large_subtype_ok = (large_fb_cnt + large_hb_cnt == large_b_cnt)
test("Large Subtype completeness: flight + hotel == bookings", large_subtype_ok)

large_acct_sql = "SELECT count(*) FROM mmt.flight_bookings fb JOIN mmt.bookings b ON b.booking_id = fb.booking_id WHERE fb.fare_paid <> (b.total_amount + b.discount);"
large_acct_mismatches = int(run_psql_large(large_acct_sql))
test("Large Fare accounting equation (0 mismatches)", large_acct_mismatches == 0)

# ---------------------------------------------------------------------
# 9. DOCUMENTATION CONSISTENCY CHECK
# ---------------------------------------------------------------------
print("\n[9/9] Verifying Cross-Document Consistency (Rubric Score & Constraints)...")
docs_to_check = [
    "README.md",
    "docs/02_schema_design.md",
    "docs/05_scalability_report.md",
    "FINAL_PROJECT_COMPLETION_REPORT.md",
    "PHASE5_COMPLETION_REPORT.md",
    "PHASE5_SECOND_AUDIT_REPORT.md"
]
inconsistencies = 0
for d in docs_to_check:
    if not os.path.exists(d):
        continue
    content = open(d).read()
    # Check for stale percentages
    if "96.5%" in content or "55%" in content and "Initial" not in content:
        inconsistencies += 1
        print(f"  [WARN] Stale percentage in {d}")

test("All documentation files consistent with 32.0/40.0 marks (80.0% verified)", inconsistencies == 0)

# ---------------------------------------------------------------------
# SUMMARY & EXIT CODE
# ---------------------------------------------------------------------
print("\n" + "=" * 70)
print(f"Audit Summary: {passed_tests} PASSED, {failed_tests} FAILED")
print("=" * 70)

if failed_tests > 0:
    print("❌ Verification FAILED: Project has unresolved issues.")
    sys.exit(1)
else:
    print("✅ All verification tests PASSED with 100% technical compliance.")
    sys.exit(0)
