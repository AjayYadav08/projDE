# Phase 3: Baseline Query Performance Timings

## 1. Methodology
- **Database Engine**: PostgreSQL 16.15 (Homebrew, aarch64-apple-darwin).
- **Measurement Harness**: `benchmarks/run_benchmark.sh` executing `EXPLAIN (ANALYZE, BUFFERS)` 3 times per query.
- **Transaction Isolation**: Write queries (`W01`–`W05`) executed inside `BEGIN ... ROLLBACK` transactions to prevent state mutation.
- **Hardware Profile**: Apple Silicon Mac, quiet system state with non-essential background processes stopped.
- **Raw Plans**: Committed in `benchmarks/results/baseline/` (`R01.txt` – `W05.txt`) and `summary.csv`.

---

## 2. Baseline Timing Table (Seed Data: 144,792 Bookings)

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|:---|:---:|---:|---:|---:|---:|
| R01: Flight search: Delhi → Mumbai on 5 July 2026 with seats left | READ | 17.274 | 16.708 | 16.488 | 16.823 |
| R02: Fare calendar: cheapest Bengaluru → Delhi fare for each day of July 2026 | READ | 2.220 | 2.629 | 2.794 | 2.548 |
| R03: Hotel search: 4★+ hotels in Goa with a swimming pool, best rated first | READ | 1.239 | 1.835 | 0.677 | 1.250 |
| R04: Room availability: rooms left per room type of hotel 208 for 10–12 July 2026 | READ | 6.162 | 7.977 | 8.021 | 7.387 |
| R05: "My Trips": customer 1021's upcoming confirmed trips | READ | 28.656 | 25.986 | 20.699 | 25.114 |
| R06: Support: open a booking by its reference | READ | 0.098 | 0.073 | 0.096 | 0.089 |
| R07: Airline manifest: passengers on flight 13047 ordered by seat | READ | 9.044 | 10.266 | 10.568 | 9.959 |
| R08: Revenue management: July 2026 flights with fewer than 5 passengers booked | READ | 21.866 | 20.107 | 16.968 | 19.647 |
| R09: Trends: 10 most-booked routes in June 2026 | READ | 40.629 | 45.101 | 37.691 | 41.140 |
| R10: Flight status board: delayed flights | READ | 1.615 | 1.738 | 1.728 | 1.694 |
| R11: Payments: bookings waiting for payment for more than 30 minutes | READ | 16.015 | 18.919 | 17.239 | 17.391 |
| R12: Finance: revenue per booking type per month in 2026 | READ | 41.860 | 36.002 | 36.235 | 38.032 |
| R13: Marketing: coupons that have never been used | READ | 29.556 | 29.250 | 27.880 | 28.895 |
| R14: Airline partnerships: cancellation rate of flight bookings per airline | READ | 71.386 | 72.171 | 68.851 | 70.803 |
| R15: Hotel partnerships: room-nights sold per city for stays in June 2026 | READ | 38.285 | 40.141 | 48.312 | 42.246 |
| R16: Insights: average days between booking and travel | READ | 151.244 | 157.736 | 147.137 | 152.039 |
| R17: Loyalty: customers with 3 or more completed trips in 2026 | READ | 45.904 | 52.660 | 50.427 | 49.664 |
| R18: Hotel page: Goa reviews that mention breakfast | READ | 7.801 | 7.798 | 8.487 | 8.029 |
| R19: Operations: passengers booked on every flight departing in June 2026 | READ | 3017.774 | 1520.191 | 2010.993 | 2182.986 |
| R20: Finance: bookings per day and running total for June 2026 | READ | 17.015 | 14.649 | 14.818 | 15.494 |
| R21: Concessions: senior-citizen passengers (60+) per route in 2026 | READ | 38.462 | 44.573 | 40.943 | 41.326 |
| R22: Support console: all bookings, newest first, page 4,001 | READ | 79.663 | 80.904 | 177.984 | 112.850 |
| R23: Sign-in: find the customer by email, ignoring case | READ | 14.047 | 14.854 | 15.133 | 14.678 |
| R24: Hotel ranking: Goa hotels with at least 5 reviews, by avg rating | READ | 3.838 | 4.533 | 5.177 | 4.516 |
| R25: Insights: last-minute flight bookings in 2026 | READ | 58.208 | 48.654 | 49.292 | 52.051 |
| W01: Checkout: create a pending flight booking for customer 1021 | WRITE | 1.367 | 2.730 | 2.805 | 2.301 |
| W02: Payment gateway callback: confirm the oldest booking waiting for payment | WRITE | 27.083 | 26.379 | 24.478 | 25.980 |
| W03: Customer cancels booking MMA7772F with a 70% refund | WRITE | 0.411 | 0.372 | 0.437 | 0.407 |
| W04: Flight ops: flights scheduled to depart before 1 July 2026 now departed | WRITE | 4.431 | 4.558 | 4.571 | 4.520 |
| W05: Front desk: assign room numbers to guests checking in on 1 July 2026 | WRITE | 8.856 | 7.907 | 8.586 | 8.450 |
| **Total (sum of all 30)** | — | **3802.009** | **2317.401** | **2875.515** | **2998.308** |

---

## 3. Plan Analysis: Scan Types and Performance Bottlenecks

- **R01**: `Seq Scan on flight_bookings`, `Seq Scan on flights`, `Index Scan on bookings_pkey`.
  *Reason*: Filtering flights by `DATE(departure_at)` is non-sargable and scans all 13,848 flights; full scan of 84,899 `flight_bookings` rows is required to aggregate seat counts.
- **R02**: `Seq Scan on flights`.
  *Reason*: Applying `departure_at::date` prevents B-tree range pruning, forcing a full scan of `flights`.
- **R03**: `Seq Scan on hotels`.
  *Reason*: Missing composite index on `(city_name, star_rating)` and JSONB path extraction (`amenities ->> 'pool'`) scans all 3,000 hotel rows.
- **R04**: `Seq Scan on hotel_bookings`, `Seq Scan on room_types`, `Index Scan on bookings_pkey`.
  *Reason*: `hotel_bookings` lacks an index on `(room_type_id, check_in, check_out)`, forcing sequential inspection of 59,893 rows.
- **R05**: `Seq Scan on bookings`, `Index Scan on flight_bookings/flights/hotel_bookings`.
  *Reason*: `bookings` lacks an index on foreign key `customer_id`, requiring a 144,792-row sequential scan to find customer 1021's single booking.
- **R06**: `Index Scan using bookings_booking_ref_key on bookings`.
  *Reason*: Extremely fast (0.089 ms) because `booking_ref` is protected by a UNIQUE B-tree index.
- **R07**: `Seq Scan on flight_bookings`, `Index Scan on bookings_pkey`, `Index Scan on passengers_pkey`.
  *Reason*: `flight_bookings` lacks a secondary index on `flight_id`, requiring a full scan of 84,899 rows to locate flight 13047.
- **R08**: `Seq Scan on flight_bookings`, `Seq Scan on flights`.
  *Reason*: Full table scans across both `flights` and `flight_bookings` to compute aggregate passenger volume.
- **R09**: `Seq Scan on bookings`, `Seq Scan on flight_bookings`, `Seq Scan on flights`.
  *Reason*: Multi-table hash joins over unindexed `booked_at` timestamp range across 144,792 bookings.
- **R10**: `Seq Scan on flights`.
  *Reason*: Scans 13,848 flights because no partial index exists for the rare status `'DELAYED'`.
- **R11**: `Parallel Seq Scan on bookings`.
  *Reason*: Scans 144,792 bookings across worker threads because no index covers `status = 'PENDING_PAYMENT'`.
- **R12**: `Parallel Seq Scan on bookings`.
  *Reason*: Multi-core parallel scan over the entire `bookings` table for 2026 data aggregation.
- **R13**: `Seq Scan on coupons`, `Seq Scan on bookings`.
  *Reason*: Nested subplan evaluates `NOT IN (SELECT coupon_code FROM bookings)`. Because `bookings.coupon_code` contains `NULL`s, SQL 3-valued logic produces 0 results after scanning 144k rows!
- **R14**: `Seq Scan on bookings`, `Seq Scan on flight_bookings`, `Seq Scan on flights`, `Seq Scan on airlines`.
  *Reason*: Four-way hash join across full relations to compute cancellation ratios.
- **R15**: `Seq Scan on bookings`, `Seq Scan on hotel_bookings`, `Seq Scan on hotels`.
  *Reason*: Unindexed date overlap condition (`check_in < '2026-07-01' AND check_out > '2026-06-01'`) forces full scan of 59,893 stays.
- **R16**: `Seq Scan on bookings`, `Seq Scan on customers`, `Seq Scan on flight_bookings`, `Seq Scan on flights`, `Seq Scan on hotel_bookings`.
  *Reason*: Heaviest analytical query (152 ms baseline); 5-table hash join and sorting without covering indexes.
- **R17**: `Parallel Seq Scan on bookings`.
  *Reason*: Parallel scan of 144,792 rows followed by hash aggregation for completed trips.
- **R18**: `Seq Scan on hotel_reviews`, `Seq Scan on hotels`.
  *Reason*: Full table scan of 15,913 reviews executing CPU-intensive `ILIKE '%breakfast%'` without trigram indexing.
- **R19**: `Seq Scan on flights`, `Seq Scan on flight_bookings`, `Index Only Scan on passengers_pkey`.
  *Reason*: **The slowest query in the benchmark (2,182.99 ms)**. Correlated subquery runs once per June flight (720 times), triggering 720 sequential scans of `flight_bookings` (84,899 rows each)!
- **R20**: `Parallel Seq Scan on bookings`.
  *Reason*: Parallel scan over `bookings` with window function cumulative aggregation.
- **R21**: `Seq Scan on passengers`, `Seq Scan on flight_bookings`, `Seq Scan on flights`.
  *Reason*: Full scans of `passengers` (163k) and `flight_bookings` (84k) joined on non-indexed columns.
- **R22**: `Seq Scan on bookings`.
  *Reason*: High latency (112.85 ms) due to deep offset pagination (`OFFSET 100000 LIMIT 25`), forcing the engine to read, sort, and discard 100,000 rows.
- **R23**: `Seq Scan on customers`.
  *Reason*: Expression `lower(email)` bypasses the standard B-tree index on `email`, scanning 40,000 rows.
- **R24**: `Seq Scan on hotel_reviews`, `Seq Scan on hotels`.
  *Reason*: Full scan on reviews grouped by hotel without index on `hotel_reviews(hotel_id, rating)`.
- **R25**: `Seq Scan on flight_bookings`, `Seq Scan on bookings`, `Seq Scan on flights`.
  *Reason*: Multi-table joins evaluating dynamic difference expression `f.departure_at - b.booked_at < interval '24 hours'`.
- **W01**: `(no scan)`.
  *Reason*: Direct tuple insertion into `bookings` (2.3 ms).
- **W02**: `Index Scan using bookings_pkey on bookings`.
  *Reason*: Evaluates `SELECT min(booking_id) FROM bookings WHERE status = 'PENDING_PAYMENT'`. Subquery requires scanning the entire `bookings` PK index because no index exists on `status`.
- **W03**: `Index Scan using bookings_booking_ref_key on bookings`.
  *Reason*: Fast point update (0.41 ms) utilizing unique index on `booking_ref`.
- **W04**: `Seq Scan on flights`.
  *Reason*: Full scan of `flights` to filter `status IN ('SCHEDULED', 'DELAYED') AND departure_at < '2026-07-01'`.
- **W05**: `Seq Scan on hotel_bookings`, `Index Scan on bookings_pkey`.
  *Reason*: Scans all 59,893 `hotel_bookings` rows looking for `check_in = '2026-07-01' AND room_number IS NULL`.
