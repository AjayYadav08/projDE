-- =====================================================================
-- MakeMyTrip DBMS Project: Partitioning Architecture (Phase 5)
-- Schema: mmt_partitioned
-- Demonstrates range partitioning on bookings by booked_at, partition pruning,
-- and primary key compliance for 100x scale.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS mmt_partitioned;
SET search_path TO mmt_partitioned;

-- ---------------------------------------------------------------------
-- 1. PostgreSQL Partitioning Rule for Primary Keys:
-- In PostgreSQL, any UNIQUE or PRIMARY KEY constraint on a partitioned
-- table MUST include all the partition key columns.
-- Therefore, the PRIMARY KEY on bookings is (booking_id, booked_at).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS bookings CASCADE;

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
    PRIMARY KEY (booking_id, booked_at)
) PARTITION BY RANGE (booked_at);

-- ---------------------------------------------------------------------
-- 2. Define Quarterly Partitions for 2025 and 2026
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
-- 3. Local Indexes automatically created on each partition
-- ---------------------------------------------------------------------
CREATE INDEX idx_part_booked_at_desc ON bookings (booked_at DESC);
CREATE INDEX idx_part_customer_status ON bookings (customer_id, status);

-- ---------------------------------------------------------------------
-- 4. Migrate data from production mmt schema
-- ---------------------------------------------------------------------
INSERT INTO bookings
SELECT * FROM mmt.bookings;

ANALYZE bookings;

-- ---------------------------------------------------------------------
-- 5. Demonstrate Partition Pruning:
-- Querying for June 2026 visits ONLY bookings_2026_q2, completely pruning
-- all other partitions from disk.
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount)
FROM bookings
WHERE booked_at >= '2026-06-01 00:00:00+05:30'
  AND booked_at <  '2026-07-01 00:00:00+05:30';

