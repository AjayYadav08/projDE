# MakeMyTrip DBMS Project: Comprehensive Viva & Individual Analysis Guide (CP5)

**Course:** Database Management Systems · **Year:** B.Tech 2nd Year  
**Target Evaluation:** CP5 Individual Analysis (40 Marks, In-Class Oral Defense)  
**Database Engine:** PostgreSQL 16  

---

## 1. Database Design & Subtyping Architecture

### Concept Explanation
In enterprise travel platforms, entities like "Bookings" share universal transactional attributes (booking reference, payment method, transaction status, discount, timestamp), but diverge into specialized domains (flights require cabins and passenger manifests; hotels require room categories, guest counts, and check-in/out dates). 
In relational modeling, this is known as the **Subtype/Supertype Design Pattern** (or Relational Specialization).

### Implementation in Our Project
We created a central master table `mmt.bookings` containing common transaction state, and specialized 1:1 subtype tables `mmt.flight_bookings` and `mmt.hotel_bookings`. Both subtype tables share `booking_id` as both their **Primary Key** and their **Foreign Key** pointing to `bookings(booking_id) ON DELETE CASCADE`.

```sql
-- Supertype Table:
CREATE TABLE bookings (
    booking_id INT PRIMARY KEY,
    booking_ref VARCHAR(20) NOT NULL UNIQUE,
    customer_id INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    booking_type VARCHAR(10) NOT NULL CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    booked_at TIMESTAMPTZ NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL CHECK (total_amount >= 0),
    ...
);

-- Specialized Subtype Table:
CREATE TABLE flight_bookings (
    booking_id INT PRIMARY KEY REFERENCES bookings(booking_id) ON DELETE CASCADE,
    flight_id INT NOT NULL REFERENCES flights(flight_id) ON DELETE RESTRICT,
    cabin VARCHAR(20) NOT NULL,
    passengers INT NOT NULL,
    fare_paid NUMERIC(10,2) NOT NULL
);
```

### Potential Viva Questions & Accurate Answers
- **Q: Why didn't you put all flight and hotel columns into a single `bookings` table?**
  - *Answer:* Single-table inheritance would introduce massive column sparsity (NULLs for hotel attributes on flight bookings and vice versa), violate 2NF/3NF due to conditional transitive dependencies, and weaken constraint integrity (e.g., checking `check_out > check_in` on a flight record).
- **Q: What is the primary key of `flight_bookings`? Can a customer have multiple flight rows per booking?**
  - *Answer:* The primary key is `booking_id`. It enforces a strict 1:1 specialization with `bookings`. Multiple tickets for different passengers on the same flight are modeled in the child `passengers` table via composite key `(booking_id, seq_no)`.

---

## 2. Entity-Relationship (ER) Diagram & Cardinalities

### Concept Explanation
Cardinality specifies the minimum and maximum instances of an entity associated with another. Relationships can be 1:1, 1:N, or M:N.

### Implementation in Our Project
- `airports` $\rightarrow$ `flights`: **1:N** for origin and **1:N** for destination.
- `airlines` $\rightarrow$ `flights`: **1:N** (one airline operates many scheduled flights).
- `flights` $\rightarrow$ `flight_bookings`: **1:N** (one flight carries many booking reservations).
- `flight_bookings` $\rightarrow$ `passengers`: **1:N** (one flight booking holds 1 to 4 passenger seats).
- `hotels` $\rightarrow$ `room_types`: **1:N** (one hotel defines standard/deluxe tiers).
- `hotels` $\rightarrow$ `hotel_bookings`: **1:N** (one property receives multiple guest stays).
- `hotel_bookings` $\rightarrow$ `hotel_reviews`: **1:1** (only completed stays can leave a single verified review; enforced by `UNIQUE` on `hotel_reviews.booking_id`).

### Potential Viva Questions & Accurate Answers
- **Q: How is the composite primary key in `passengers` defined and why?**
  - *Answer:* `PRIMARY KEY (booking_id, seq_no)`. `booking_id` identifies the reservation, while `seq_no` (1, 2, 3...) represents passenger ordinals within that ticket. It eliminates the overhead of a synthetic surrogate key and guarantees that passenger ordinals are distinct within each itinerary.
- **Q: Why does `hotel_reviews` have a foreign key to `hotel_id` if it already references `booking_id`?**
  - *Answer:* While `booking_id` points to `hotel_bookings`, which contains `hotel_id`, denormalizing `hotel_id` directly onto `hotel_reviews` enables high-throughput ranking queries (`R18`, `R24`) to aggregate ratings per hotel without joining the 59,893-row `hotel_bookings` table.

---

## 3. Normalization & Functional Dependencies (3NF / BCNF)

### Concept Explanation
- **1NF:** Atomic attribute values, no repeating groups.
- **2NF:** 1NF + no partial functional dependencies (every non-key attribute is fully functionally dependent on the entire candidate key).
- **3NF:** 2NF + no transitive functional dependencies ($X \rightarrow Y$ implies $X$ is a superkey or $Y$ is a prime attribute).
- **BCNF:** For every non-trivial functional dependency $X \rightarrow Y$, $X$ must be a superkey.

### Implementation in Our Project
All tables are in **BCNF**:
- `customers`: Key is `customer_id`. Functional dependencies: `customer_id -> full_name, email, phone, loyalty_tier, created_at`. Candidate keys: `customer_id`, `email`, `phone`. All determinants are candidate keys $\rightarrow$ BCNF.
- `passengers`: Key is `(booking_id, seq_no)`. Dependencies: `(booking_id, seq_no) -> full_name, age, gender, seat_no`. No partial key dependencies $\rightarrow$ BCNF.

#### Derived Column Justification:
- `flight_bookings.fare_paid` vs `bookings.total_amount + discount`: 
  In travel accounting, `fare_paid` stores gross ticketing tariff before coupon subsidies, while `total_amount` is net payable. We proved on all 84,899 rows that `fare_paid = total_amount + discount`.
- `flight_bookings.passengers` vs row counts in `passengers`:
  Denormalizing passenger volume on the booking summary avoids expensive 163,000-row hash joins during seat count calculations (`R01`, `R08`).

### Potential Viva Questions & Accurate Answers
- **Q: Is a table containing a JSONB column (like `hotels.amenities`) in 1NF?**
  - *Answer:* Yes. In relational theory, an attribute is atomic if the DBMS and domain treat it as an indivisible structured value. In PostgreSQL, `JSONB` is a native binary data type with standard operations and internal indexing (GIN). Furthermore, amenities are unstructured key-value flags that vary per property; creating a separate junction table would require continuous schema updates for new hotel features.

---

## 4. Constraints, Integrity & `ON DELETE` Rules

### Concept Explanation
Constraints enforce database consistency at the engine level rather than relying on application code.
- `ON DELETE RESTRICT`: Blocks deletion of a parent record if children exist (guards referential integrity).
- `ON DELETE CASCADE`: Deletes child records automatically when parent is removed.
- `ON DELETE SET NULL`: Sets child foreign key to NULL upon parent deletion.

### Implementation in Our Project
We defined **64 explicit constraints in `pg_constraint`** (including 33 named domain `CHECK` constraints, 14 `FOREIGN KEY` constraints, 12 `PRIMARY KEY` constraints, and 5 `UNIQUE` constraints) plus 74 column-level `NOT NULL` constraints in `sql/01_schema.sql`.

Key domain CHECK constraint examples:
1. `chk_flights_schedule`: `arrival_at > departure_at`
2. `chk_flights_route`: `origin <> destination`
3. `chk_hotel_bookings_dates`: `check_out > check_in`
4. `chk_bookings_cancellation`:
   ```sql
   CONSTRAINT chk_bookings_cancellation CHECK (
       (status = 'CANCELLED' AND cancelled_at IS NOT NULL AND refund_amount IS NOT NULL) OR
       (status <> 'CANCELLED' AND cancelled_at IS NULL AND refund_amount IS NULL)
   )
   ```
5. `chk_bookings_coupon_discount`: `(discount = 0.00) OR (discount > 0.00 AND coupon_code IS NOT NULL)`

#### Foreign Key Delete Rules:
- `customers` $\rightarrow$ `bookings`: `ON DELETE RESTRICT` (prevents deleting active accounts with commercial history).
- `bookings` $\rightarrow$ `flight_bookings` / `hotel_bookings`: `ON DELETE CASCADE` (if a booking is purged, its subtype payload is purged).
- `coupons` $\rightarrow$ `bookings`: `ON DELETE SET NULL` (deleting an expired promo campaign must not delete customer historical bookings).

### Potential Viva Questions & Accurate Answers
- **Q: Why is `ON DELETE RESTRICT` used between `airports` and `flights`?**
  - *Answer:* An airport cannot be deleted from the database if there are historical or scheduled flights routed through it; doing so would corrupt navigational flight logs and partner settlement audits.

---

## 5. The R13 Bug: Three-Valued Logic & NULL Traps

### Concept Explanation
SQL uses Three-Valued Logic (3VL): `TRUE`, `FALSE`, and `UNKNOWN`. 
When evaluating `WHERE col NOT IN (SELECT sub_col FROM table)`:
If the subquery returns even a single `NULL`, the expression evaluates to `UNKNOWN` for every outer row:
$$x \text{ NOT IN } (v_1, v_2, \text{NULL}) \iff (x \ne v_1) \land (x \ne v_2) \land (x \ne \text{NULL})$$
Since `x <> NULL` is `UNKNOWN`, any condition `TRUE AND UNKNOWN` yields `UNKNOWN`, and the `WHERE` clause filters out **all rows**.

### Implementation in Our Project
- **Baseline Query (`R13`):**
  ```sql
  SELECT c.coupon_code, c.applies_to, c.discount_pct
  FROM coupons c
  WHERE c.coupon_code NOT IN (SELECT b.coupon_code FROM bookings b);
  ```
  In `bookings`, 127,144 rows have `coupon_code IS NULL`. Consequently, the baseline query returned **0 rows**, exactly matching Problem P6 reported by marketing!
- **Our Optimized Rewrite:**
  ```sql
  SELECT c.coupon_code, c.applies_to, c.discount_pct
  FROM coupons c
  WHERE NOT EXISTS (SELECT 1 FROM bookings b WHERE b.coupon_code = c.coupon_code);
  ```
  `NOT EXISTS` tests for row existence (two-valued logic). It correctly surfaced all **10 unused coupons** in **0.34 ms**!

### Potential Viva Questions & Accurate Answers
- **Q: What other way could you fix R13 without using `NOT EXISTS`?**
  - *Answer:* By adding a `WHERE b.coupon_code IS NOT NULL` clause inside the subquery:
    `WHERE c.coupon_code NOT IN (SELECT b.coupon_code FROM bookings b WHERE b.coupon_code IS NOT NULL)`. However, `NOT EXISTS` is generally preferred because the query planner turns it into an anti-join with index early exit.

---

## 6. The R19 Optimization: Correlated Subqueries vs Set-Based Joins

### Concept Explanation
A **correlated subquery** references columns from the outer query. The query engine must execute the inner subquery repeatedly—once for every outer row—yielding $O(M \times N)$ execution time.
A **set-based join** combines both relations in memory using hash joins or merge joins in $O(M + N)$ time.

### Implementation in Our Project
- **Baseline Query (`R19`):**
  ```sql
  SELECT f.flight_id, f.flight_no, f.departure_at,
         (SELECT count(*) FROM passengers p 
          JOIN flight_bookings fb ON fb.booking_id = p.booking_id 
          WHERE fb.flight_id = f.flight_id) AS passengers
  FROM flights f
  WHERE f.departure_at >= '2026-06-01' AND f.departure_at < '2026-07-01'
  ORDER BY passengers DESC, f.departure_at;
  ```
  *Bottleneck:* For 720 flights in June 2026, it performed 720 full sequential scans of `flight_bookings` (85,000 rows each), scanning 61 million tuples and taking **2,182.99 ms**.
- **Our Optimized Rewrite (`sql/06_optimized_queries.sql`):**
  ```sql
  SELECT f.flight_id, f.flight_no, f.departure_at,
         count(p.seq_no) AS passengers
  FROM flights f
  LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
  LEFT JOIN passengers p       ON p.booking_id = fb.booking_id
  WHERE f.departure_at >= '2026-06-01' AND f.departure_at < '2026-07-01'
  GROUP BY f.flight_id, f.flight_no, f.departure_at
  ORDER BY passengers DESC, f.departure_at;
  ```
  *Result:* PostgreSQL joins June flights and bookings in a single pass, dropping runtime from **2,182.99 ms to 26.17 ms (83× speedup)**.

### Potential Viva Questions & Accurate Answers
- **Q: Why did you use `count(p.seq_no)` instead of `count(*)` in the group-by join?**
  - *Answer:* In a `LEFT JOIN`, if a flight has zero bookings, `count(*)` would evaluate to 1 (because the null-padded outer row exists), whereas `count(p.seq_no)` correctly evaluates to 0 because `p.seq_no` is NULL.

---

## 7. Indexing Strategies (B-Tree, Partial, Covering, Expression, GIN)

### Concept Explanation & Project Examples

| Index Type | When to Use | Example from Our Project | How It Accelerated Query |
|:---|:---|:---|:---|
| **Composite B-Tree** | Multi-column filtering; equality columns first, then range/sort | `idx_flights_route_date_fare ON flights (origin, destination, departure_at, base_fare)` | Accelerated `R02` from 2.55 ms to 0.38 ms. |
| **Covering Index (`INCLUDE`)** | Eliminates heap fetches; all select columns live in index leaf pages | `idx_flights_search ON flights (origin, destination, departure_at) INCLUDE (flight_no, arrival_at, base_fare, total_seats)` | Enabled **Index Only Scan** for `R01` (0.32 ms). |
| **Partial Index** | Index only a small, frequently-queried subset of rows (`WHERE ...`) | `idx_bookings_pending_payment ON bookings (booking_id, booked_at) WHERE status = 'PENDING_PAYMENT'` | Indexes only 111 pending checkouts out of 144k rows; accelerated `R11` from 17.4 ms to 0.21 ms and `W02` from 26 ms to 2.2 ms. |
| **Expression Index** | Filters query against an evaluated function | `idx_customers_lower_email ON customers (lower(email)) INCLUDE (customer_id, full_name, loyalty_tier)` | Standard B-trees cannot index function calls; this accelerated case-insensitive login `R23` from 14.7 ms to 0.13 ms. |
| **GIN Trigram Index (`pg_trgm`)** | Arbitrary substring searches (`ILIKE '%term%'`) | `idx_hotel_reviews_text_trgm ON hotel_reviews USING gin (review_text gin_trgm_ops)` | Transforms full table scans on review text (`R18`) into logarithmic trigram lookups (2.6 ms). |

### Potential Viva Questions & Accurate Answers
- **Q: Why does column order matter in a composite B-tree index?**
  - *Answer:* A composite index on `(A, B, C)` is sorted primarily by `A`, then by `B` within equal `A` values, then by `C`. A query filtering on `B` alone cannot use the index effectively. The rule is: equality columns first, followed by range/sort columns.
- **Q: What is the difference between an Index Scan and an Index Only Scan?**
  - *Answer:* An **Index Scan** finds matching tuple IDs (TIDs) in the index leaf pages and then visits the table heap to retrieve remaining column values or check tuple visibility. An **Index Only Scan** retrieves all required columns directly from the index payload (via `INCLUDE`), consulting only the PostgreSQL Visibility Map, avoiding heap random I/O.

---

## 8. Query Execution Plans & Scan Nodes

### Concept Explanation
PostgreSQL cost-based optimizer (CBO) evaluates available execution paths:
- `Seq Scan`: Reads sequential disk blocks from the table heap. Fast for large fractions of a table (> 15–20%), but slow for selective lookups.
- `Index Scan`: Traverses B-tree root $\rightarrow$ branch $\rightarrow$ leaf $\rightarrow$ table heap.
- `Bitmap Index Scan / Bitmap Heap Scan`: Used when multiple index rows match; constructs a bitmap of physical page addresses in memory, sorts by block ID, and reads heap pages sequentially.
- `Hash Join` vs `Nested Loop`: Nested Loop is chosen for small outer datasets with index lookups; Hash Join is chosen for joining medium-to-large unindexed sets.

### Potential Viva Questions & Accurate Answers
- **Q: Why did `R14` (airline cancellation rate) still perform a Sequential Scan even after indexes were created?**
  - *Answer:* `R14` computes historical cancellation percentages across all 84,899 flight bookings. Because the query must read nearly 100% of the table, using an index would cause 85,000 random I/O lookups. Sequential scanning through contiguous disk blocks using parallel background workers is significantly faster.

---

## 9. Deep Pagination: OFFSET vs Keyset (Seek) Pagination

### Concept Explanation
- **`OFFSET N LIMIT M`:** The database must read all $N$ rows, sort them, and discard $N$ tuples before returning $M$ rows. Time complexity is $O(N)$.
- **Keyset Pagination (Seek Method):** Uses a deterministic composite cursor `(booked_at, booking_id) < (:last_ts, :last_id)` to seek directly to the index leaf page in $O(\log N)$ time.

### Implementation in Our Project (`R22`)
- **Baseline (`OFFSET 100000 LIMIT 25`):** 112.85 ms (reads 100,000 rows).
- **Optimized B-tree Offset:** 25.41 ms (traverses 2,084 index leaf pages).
- **Keyset Seek Query:**
  ```sql
  SELECT booking_id, booking_ref, booking_type, status, total_amount, booked_at
  FROM bookings
  WHERE (booked_at, booking_id) < ('2025-06-18 22:12:10+05:30', 46409)
  ORDER BY booked_at DESC, booking_id DESC
  LIMIT 25;
  ```
  *Measured Result:* Executes in **0.275 ms** using only **4 buffer page hits** (a >90× improvement over Phase 4 offset scan).

### Potential Viva Questions & Accurate Answers
- **Q: Why must descending keyset pagination use strict `<` instead of `<=`?**
  - *Answer:* If `<=` is used, the boundary record at the bottom of Page $N$ is re-evaluated and returned as the first record of Page $N+1$, resulting in duplicate records across pages. Strict `<` mathematically guarantees 100% disjoint, gap-free consecutive pages identical to `OFFSET` pagination.
- **Q: Why must keyset pagination include `booking_id` alongside `booked_at`?**
  - *Answer:* `booked_at` is not strictly unique; multiple customers can book at the exact same second. Combining `(booked_at, booking_id)` guarantees a deterministic, tie-broken cursor that prevents skipping or duplicating rows across page boundaries.

---

## 10. Declarative Partitioning & Architecture for 100× Scale

### Concept Explanation
Partitioning divides a large logical table into smaller physical tables (partitions) based on a key (Range, List, Hash).
- **Partition Pruning:** The query optimizer inspects `WHERE` clauses at planning or execution time and excludes non-matching partitions from the scan tree.

### Implementation in Our Project (`sql/08_partitioning.sql`)
1. Partitioned `bookings` by `RANGE (booked_at)` into 8 quarterly partitions (2025–2026) + default.
2. **PostgreSQL Primary Key Rule:** Any `PRIMARY KEY` or `UNIQUE` constraint on a partitioned table must include the partition key columns $\rightarrow$ `PRIMARY KEY (booking_id, booked_at)`.
3. **Co-Partitioning:** Child table `flight_bookings` is also partitioned by `(booked_at)` with composite key `(booking_id, booked_at)`.
4. **Demonstrated Pruning:** Querying June 2026 accessed only `bookings_2026_q2` in **2.16 ms**, pruning all other 8 partitions.
5. **Partition Archival Locks & Order:**
   - Ordinary `DETACH PARTITION` acquires `ACCESS EXCLUSIVE` lock on the partitioned table (brief catalog lock, not zero-downtime).
   - `DETACH PARTITION CONCURRENTLY` cannot be used when a `DEFAULT` partition exists.
   - Child partition `fb_2025_q1` must be detached before parent partition `bookings_2025_q1`, and the inherited FK dropped on the detached child before detaching the parent partition.

### Potential Viva Questions & Accurate Answers
- **Q: Can you detach partitions concurrently in zero downtime?**
  - *Answer:* In PostgreSQL 14+, `ALTER TABLE ... DETACH PARTITION ... CONCURRENTLY` acquires `SHARE UPDATE EXCLUSIVE` lock instead of `ACCESS EXCLUSIVE`. However, PostgreSQL explicitly forbids `CONCURRENTLY` if a `DEFAULT` partition exists. Because our schema includes a default partition for future and unrouted dates, partition detachment must use standard `DETACH PARTITION` during scheduled maintenance windows.
- **Q: Why did you choose Range Partitioning on `booked_at` instead of Hash Partitioning on `customer_id`?**
  - *Answer:* Travel reservations are naturally time-series data. 95% of queries filter on recent or upcoming travel dates (`R09`, `R12`, `R20`). Range partitioning enables partition pruning for time-window queries and facilitates zero-downtime cold storage archival (`DETACH PARTITION` old quarters).
- **Q: Why did you co-partition `flight_bookings`?**
  - *Answer:* In PostgreSQL, you cannot detach a parent partition if a foreign key from an unpartitioned table references it. Co-partitioning parent and child on the identical time boundary allows detaching entire quarters from both tables simultaneously for S3 archival.

