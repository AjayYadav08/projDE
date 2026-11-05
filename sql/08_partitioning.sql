-- =====================================================================
-- MakeMyTrip DBMS Project: Advanced Partitioning Architecture (Phase 5)
-- Schema: mmt_partitioned
-- Database: PostgreSQL 16
-- Demonstrates:
--   1. Declarative Range Partitioning on bookings by booked_at
--   2. PostgreSQL Primary Key & Constraint Rules for Partitioned Tables
--   3. Co-partitioning of Child Specialization Tables (flight_bookings)
--   4. Local Partition Indexes (Composite B-tree, Partial)
--   5. Partition Pruning Proofs (Single-Quarter, Point, Multi-Quarter, Keyset)
--   6. Zero-Downtime Data Lifecycle Archival (Co-partition DETACH / ATTACH)
-- =====================================================================

DROP SCHEMA IF EXISTS mmt_partitioned CASCADE;
CREATE SCHEMA mmt_partitioned;
SET search_path TO mmt_partitioned;

-- ---------------------------------------------------------------------
-- 1. PostgreSQL Declarative Partitioning Primary Key Rule:
-- In PostgreSQL, any UNIQUE or PRIMARY KEY constraint on a partitioned
-- table MUST include all columns from the partition key.
-- Therefore, the PRIMARY KEY on bookings is (booking_id, booked_at).
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
    booking_id INT NOT NULL,
    booking_ref VARCHAR(20) NOT NULL,
    customer_id INT NOT NULL,
    booking_type VARCHAR(10) NOT NULL,
    booked_at TIMESTAMPTZ NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    coupon_code VARCHAR(30),
    discount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    payment_method VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    cancelled_at TIMESTAMPTZ,
    refund_amount NUMERIC(10,2),
    PRIMARY KEY (booking_id, booked_at),
    CONSTRAINT chk_part_bookings_type CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    CONSTRAINT chk_part_bookings_payment_method CHECK (payment_method IN ('CARD', 'NETBANKING', 'UPI', 'WALLET', 'EMI')),
    CONSTRAINT chk_part_bookings_status CHECK (status IN ('CONFIRMED', 'COMPLETED', 'CANCELLED', 'PENDING_PAYMENT')),
    CONSTRAINT chk_part_bookings_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_part_bookings_discount CHECK (discount >= 0),
    CONSTRAINT chk_part_bookings_cancellation CHECK (
        (status = 'CANCELLED' AND cancelled_at IS NOT NULL AND refund_amount IS NOT NULL) OR
        (status <> 'CANCELLED' AND cancelled_at IS NULL AND refund_amount IS NULL)
    ),
    CONSTRAINT chk_part_bookings_refund CHECK (refund_amount IS NULL OR refund_amount <= total_amount)
) PARTITION BY RANGE (booked_at);

-- ---------------------------------------------------------------------
-- 2. Define Quarterly Partitions for bookings (2025 - 2026) + Default
-- ---------------------------------------------------------------------
CREATE TABLE bookings_2025_q1 PARTITION OF bookings
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q2 PARTITION OF bookings
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q3 PARTITION OF bookings
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q4 PARTITION OF bookings
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q1 PARTITION OF bookings
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q2 PARTITION OF bookings
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q3 PARTITION OF bookings
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q4 PARTITION OF bookings
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');

CREATE TABLE bookings_default PARTITION OF bookings DEFAULT;

-- ---------------------------------------------------------------------
-- 3. Local Partition Indexes (Automatically Propagated to Each Partition)
-- ---------------------------------------------------------------------
CREATE INDEX idx_part_booked_at_keyset
    ON bookings (booked_at DESC, booking_id DESC)
    INCLUDE (booking_ref, booking_type, status, total_amount);

CREATE INDEX idx_part_customer_status
    ON bookings (customer_id, status)
    INCLUDE (booking_ref, booking_type, total_amount);

CREATE INDEX idx_part_pending_payment
    ON bookings (booking_id, booked_at)
    WHERE status = 'PENDING_PAYMENT';

-- ---------------------------------------------------------------------
-- 4. Co-Partitioning Child Specialization Tables (flight_bookings)
-- To enable clean partition lifecycle management (e.g. archiving an entire quarter),
-- child tables are co-partitioned on the identical partition key (booked_at).
-- ---------------------------------------------------------------------
CREATE TABLE flight_bookings (
    booking_id INT NOT NULL,
    booked_at TIMESTAMPTZ NOT NULL,
    flight_id INT NOT NULL,
    cabin VARCHAR(20) NOT NULL,
    passengers INT NOT NULL,
    fare_paid NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (booking_id, booked_at)
) PARTITION BY RANGE (booked_at);

CREATE TABLE fb_2025_q1 PARTITION OF flight_bookings
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
CREATE TABLE fb_2025_q2 PARTITION OF flight_bookings
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');
CREATE TABLE fb_2025_q3 PARTITION OF flight_bookings
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');
CREATE TABLE fb_2025_q4 PARTITION OF flight_bookings
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');
CREATE TABLE fb_2026_q1 PARTITION OF flight_bookings
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');
CREATE TABLE fb_2026_q2 PARTITION OF flight_bookings
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');
CREATE TABLE fb_2026_q3 PARTITION OF flight_bookings
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');
CREATE TABLE fb_2026_q4 PARTITION OF flight_bookings
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');
CREATE TABLE fb_default PARTITION OF flight_bookings DEFAULT;

CREATE INDEX idx_fb_part_flight ON flight_bookings (flight_id);

-- ---------------------------------------------------------------------
-- 5. Data Migration from Production Schema
-- ---------------------------------------------------------------------
INSERT INTO bookings
SELECT * FROM mmt.bookings;

INSERT INTO flight_bookings
SELECT fb.booking_id, b.booked_at, fb.flight_id, fb.cabin, fb.passengers, fb.fare_paid
FROM mmt.flight_bookings fb
JOIN mmt.bookings b ON b.booking_id = fb.booking_id;

ANALYZE bookings;
ANALYZE flight_bookings;

-- ---------------------------------------------------------------------
-- 6. PARTITION PRUNING DEMONSTRATIONS
-- ---------------------------------------------------------------------

-- Demonstration 6A: Single-Quarter Range Pruning
-- Targeted range: June 2026.
-- Expected plan: Scans ONLY bookings_2026_q2; all other 8 partitions pruned.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount)
FROM bookings
WHERE booked_at >= '2026-06-01 00:00:00+05:30'
  AND booked_at <  '2026-07-01 00:00:00+05:30';

-- Demonstration 6B: Point Timestamp Pruning
-- Targeted timestamp: 15 Feb 2025.
-- Expected plan: Scans ONLY bookings_2025_q1.
EXPLAIN (ANALYZE, BUFFERS)
SELECT booking_id, booking_ref, total_amount
FROM bookings
WHERE booked_at = '2025-02-15 14:30:00+05:30';

-- Demonstration 6C: Multi-Quarter Range Pruning
-- Targeted range: November 2025 through February 2026.
-- Expected plan: Scans ONLY bookings_2025_q4 and bookings_2026_q1 (2 of 9 partitions).
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', booked_at) AS m, count(*)
FROM bookings
WHERE booked_at >= '2025-11-01 00:00:00+05:30'
  AND booked_at <  '2026-03-01 00:00:00+05:30'
GROUP BY 1;

-- Demonstration 6D: Keyset Pagination on Partitioned Table
-- Keyset seek directly through partition boundary without reading old tuples.
EXPLAIN (ANALYZE, BUFFERS)
SELECT booking_id, booking_ref, booking_type, status, total_amount, booked_at
FROM bookings
WHERE (booked_at, booking_id) <= ('2025-06-18 22:12:10+05:30', 46409)
ORDER BY booked_at DESC, booking_id DESC
LIMIT 25;

-- ---------------------------------------------------------------------
-- 7. PARTITION MANAGEMENT & ARCHIVAL (DETACH / ATTACH)
-- Demonstrates zero-downtime cold partition archival via co-partitioning
-- ---------------------------------------------------------------------
-- Step 7A: Detach old quarter from child table and master table
ALTER TABLE flight_bookings DETACH PARTITION fb_2025_q1;
ALTER TABLE bookings DETACH PARTITION bookings_2025_q1;

-- Step 7B: Verify query on bookings now completely excludes 2025_q1:
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM bookings WHERE booked_at >= '2025-01-01' AND booked_at < '2025-04-01';

-- Step 7C: Re-attach seamlessly:
ALTER TABLE bookings ATTACH PARTITION bookings_2025_q1
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
ALTER TABLE flight_bookings ATTACH PARTITION fb_2025_q1
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
