# MakeMyTrip Travel Booking Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 12 CSV files (144,792 bookings): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details (fill in before you start)

| Role | Name | Enrollment No. | GitHub Username |
|------|------|----------------|-----------------|
| Group Lead | | | |
| Member 2 | | | |
| Member 3 | | | |
| Member 4 | | | |

**Team No.:** ____ · **Section:** ____ · **Repository URL:** ____

---

## How this project works

| Phase | What you do | You submit | Counts toward | Marks |
|-------|-------------|------------|---------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | Query Execution | 2 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | Query Execution | 5 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | Query Execution | 3 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | Code Optimization | 16 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | Code Optimization | 14 |
| | **Total** | | | **40** |

---

## Phase 1: Problem statements

MakeMyTrip sells **flights** and **hotel stays**. Every flight is a dated instance of an airline's flight number between two airports (identified by IATA codes like DEL, BOM). Hotels have room types with a fixed number of rooms and a set of amenities. A customer makes a **booking**—either a flight booking (with one or more passengers who later get seats at web check-in) or a hotel booking (dates, rooms, guests; room numbers are given at check-in). Bookings can use coupons, wait for payment, be cancelled with a refund, and hotel stays can be reviewed. You have joined the MakeMyTrip data team.

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "**Flight search** and the **fare calendar** are too slow, and seats-left numbers lag." | Flights | R01, R02, R10 |
| P2 | "**Hotel search** with amenity filters and **room availability** for date ranges are slow." | Hotels | R03, R04, R18, R24 |
| P3 | "**My Trips**, booking lookup by reference and sign-in lag." | Customer app | R05, R06, R23 |
| P4 | "Airlines need passenger **manifests**, low-load reports and cancellation rates fast." | Airline partners | R07, R08, R14, R19, W04 |
| P5 | "**Checkout and payments**: pending-payment queue, confirmations and cancellations are slow under load." | Payments | R11, W01, W02, W03 |
| P6 | "Marketing's "**coupons never used**" report always returns **nothing**." | Marketing | R13 |
| P7 | "Hotel partners want **room-nights per city**; the front desk needs fast check-in updates." | Hotel partners | R15, W05 |
| P8 | "Finance, loyalty and insight reports (revenue, lead time, repeat customers, last-minute bookings, routes, concessions) time out, and bookings will grow **20×**." | Finance / Insights | R09, R12, R16, R17, R20, R21, R22, R25 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P8, write in your own words what the business needs and which **stakeholder** is affected (traveller, airline partner, hotel partner, revenue management, payments, marketing, loyalty team, customer support, front desk).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 12 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `airports.csv` | 16 | Airports (IATA codes) |
| `airlines.csv` | 5 | Airlines (IATA airline codes) |
| `flights.csv` | 13,848 | Dated flights, 1 Jan 2025 – 31 Jul 2026 |
| `hotels.csv` | 3,000 | Hotels (with amenities) |
| `room_types.csv` | 9,000 | Room types of each hotel |
| `customers.csv` | 40,000 | MakeMyTrip customers |
| `coupons.csv` | 30 | Discount coupons |
| `bookings.csv` | 144,792 | Every booking made from 1 Jan 2025 to 30 Jun 2026 |
| `flight_bookings.csv` | 84,899 | Flight details of flight bookings |
| `passengers.csv` | 163,380 | Passengers on each flight booking |
| `hotel_bookings.csv` | 59,893 | Stay details of hotel bookings |
| `hotel_reviews.csv` | 15,913 | Reviews of completed hotel stays |

The first line of every file is the header (column names). Here are the headers and the first rows of each file:

**airports.csv**
```
iata_code,airport_name,city_name,country_code
AMD,Sardar Vallabhbhai Patel International,Ahmedabad,IN
BLR,Kempegowda International,Bengaluru,IN
```

**airlines.csv**
```
airline_code,airline_name
6E,IndiGo
AI,Air India
```

**flights.csv**
```
flight_id,airline_code,flight_no,origin,destination,departure_at,arrival_at,aircraft,total_seats,base_fare,status
1,6E,6E-137,DEL,BOM,2025-01-01 06:11:00+05:30,2025-01-01 08:21:00+05:30,A320neo,186,4836.00,LANDED
2,AI,AI-174,BOM,DEL,2025-01-01 06:52:00+05:30,2025-01-01 09:07:00+05:30,A320neo,186,5076.00,LANDED
```

**hotels.csv**
```
hotel_id,hotel_name,city_name,star_rating,user_rating,amenities,check_in_time,check_out_time
1,Sea Breeze Udaipur,Udaipur,3,5.0,"{""gym"": true, ""spa"": false, ""pool"": false, ""wifi"": true, ""parking"": true, ""breakfast"": true, ""pet_friendly"": false}",14:00:00,11:00:00
2,Royal Heritage Hyderabad,Hyderabad,5,3.0,"{""gym"": true, ""spa"": false, ""pool"": false, ""wifi"": true, ""parking"": true, ""breakfast"": true, ""pet_friendly"": false}",14:00:00,11:00:00
```

**room_types.csv**
```
room_type_id,hotel_id,room_name,max_guests,price_per_night,total_rooms
1,1,Standard Room,2,3145.00,21
2,1,Deluxe Room,3,4403.00,13
```

**customers.csv**
```
customer_id,full_name,email,phone,loyalty_tier,created_at
1,Vivaan Sharma,vivaan.sharma1@Rediffmail.com,8800000001,BLUE,2024-04-05 11:31:27+05:30
2,Aditya Sharma,aditya.sharma2@Rediffmail.com,8800000002,GOLD,2021-06-26 05:00:47+05:30
```

**coupons.csv**
```
coupon_code,applies_to,discount_pct,max_discount,valid_from,valid_to
DIWALI19,HOTEL,8,1500.00,2024-12-01,2026-12-31
DIWALI29,ALL,20,1500.00,2024-12-01,2026-12-31
```

**bookings.csv**
```
booking_id,booking_ref,customer_id,booking_type,booked_at,total_amount,coupon_code,discount,payment_method,status,cancelled_at,refund_amount
1,MM01B808,11762,HOTEL,2025-01-01 00:00:00+05:30,15096.00,,0.00,CARD,COMPLETED,,
2,MM035121,36050,FLIGHT,2025-01-01 00:05:14+05:30,24592.00,,0.00,NETBANKING,COMPLETED,,
```

**flight_bookings.csv**
```
booking_id,flight_id,cabin,passengers,fare_paid
2,200,ECONOMY,4,24592.00
6,1156,PREMIUM,1,10572.80
```

**passengers.csv**
```
booking_id,seq_no,full_name,age,gender,seat_no
2,1,Aarav Iyer,24,M,16D
2,2,Kavya Iyer,5,X,17E
```

**hotel_bookings.csv**
```
booking_id,hotel_id,room_type_id,check_in,check_out,rooms,guests,room_number
1,964,2892,2025-02-07,2025-02-09,1,2,208
3,504,1510,2025-01-16,2025-01-17,1,3,422
```

**hotel_reviews.csv**
```
review_id,booking_id,hotel_id,rating,title,review_text,created_at
1,25,1644,3,Excellent location,Breakfast spread was amazing,2025-01-20 17:00:00+05:30
2,29,1046,3,Wonderful stay,,2025-01-09 15:00:00+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, timestamps with a time-zone offset, yes/no columns, small whole numbers, decimals and short codes.
3. **Primary key.** Is it one column, or a combination? (Can a 3-letter airport code be a primary key? How are `flight_bookings` and `hotel_bookings` related to `bookings`—what is their primary key? Look closely at `passengers`.)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why**, and decide which columns must never be empty. When are `coupon_code`, `cancelled_at`, `refund_amount`, `seat_no`, `room_number`, `user_rating` and `review_text` empty?
6. **UNIQUE** columns (natural candidate keys such as emails, phone numbers, codes and handles).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Look for formats (IATA codes, flight numbers, booking references, seat numbers), allowed values (statuses, cabins, payment methods, tiers), date/time order (arrival after departure, check-out after check-in), and rules tying columns together (cancelled ⇔ cancellation time, refund only when cancelled and never more than paid, no discount without a coupon, origin ≠ destination). What kind of data is in `amenities`?
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: `flight_bookings.fare_paid` vs `bookings.total_amount` + `discount`; `flight_bookings.passengers` vs rows in `passengers`; `hotel_reviews.hotel_id` vs the booking's hotel) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`mmt`**: `CREATE SCHEMA mmt;` and `SET search_path TO mmt;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO mmt;
\copy airports FROM 'seed_data/airports.csv' WITH (FORMAT csv, HEADER true)
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "every flight booking has exactly as many passenger rows as its `passengers` count", "no flight was booked after it departed", "a booking is either a flight booking or a hotel booking, never both"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 12 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 25 reads (`R01`–`R25`) and 5 writes (`W01`–`W05`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W05`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **noticeably longer** than the others on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Flight search: Delhi → Mumbai on 5 July 2026 with seats left | READ | | | | |
| R02: Fare calendar: cheapest Bengaluru → Delhi fare for each day of July 2026 | READ | | | | |
| R03: Hotel search: 4★+ hotels in Goa with a swimming pool, best rated first | READ | | | | |
| R04: Room availability: rooms left per room type of hotel 208 for 10–12 July 2026 | READ | | | | |
| R05: "My Trips": customer 1021's upcoming confirmed trips | READ | | | | |
| R06: Support: open a booking by its reference | READ | | | | |
| R07: Airline manifest: passengers on flight 13047 ordered by seat | READ | | | | |
| R08: Revenue management: July 2026 flights with fewer than 5 passengers booked | READ | | | | |
| R09: Trends: 10 most-booked routes in June 2026 | READ | | | | |
| R10: Flight status board: delayed flights | READ | | | | |
| R11: Payments: bookings waiting for payment for more than 30 minutes (checked at 23:59 on 30 Jun 2026) | READ | | | | |
| R12: Finance: revenue per booking type per month in 2026 (excluding cancellations) | READ | | | | |
| R13: Marketing: coupons that have never been used | READ | | | | |
| R14: Airline partnerships: cancellation rate of flight bookings per airline | READ | | | | |
| R15: Hotel partnerships: room-nights sold per city for stays in June 2026 | READ | | | | |
| R16: Insights: average days between booking and travel, per booking type and loyalty tier | READ | | | | |
| R17: Loyalty: customers with 3 or more completed trips that started in 2026 | READ | | | | |
| R18: Hotel page: Goa reviews that mention breakfast | READ | | | | |
| R19: Operations: passengers booked on every flight departing in June 2026 | READ | | | | |
| R20: Finance: bookings per day and running total for June 2026 | READ | | | | |
| R21: Concessions: senior-citizen passengers (60+) per route in 2026 | READ | | | | |
| R22: Support console: all bookings, newest first, page 4,001 (25 per page) | READ | | | | |
| R23: Sign-in: find the customer by email, ignoring case | READ | | | | |
| R24: Hotel ranking: Goa hotels with at least 5 reviews, by average review rating | READ | | | | |
| R25: Insights: last-minute flight bookings (made less than 24 hours before departure) in 2026 | READ | | | | |
| W01: Checkout: create a pending flight booking for customer 1021 | WRITE | | | | |
| W02: Payment gateway callback: confirm the oldest booking that is waiting for payment | WRITE | | | | |
| W03: Customer cancels booking MMA7772F with a 70% refund | WRITE | | | | |
| W04: Flight ops: every flight that was scheduled to depart before 1 July 2026 has now departed | WRITE | | | | |
| W05: Front desk: assign room numbers to every guest checking in on 1 July 2026 | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN index | for `ILIKE '%text%'` (extension `pg_trgm`), arrays or full-text search |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination; `UNION ALL` instead of `OR` across columns |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule about NULLs. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01 | | e.g. Seq Scan on flights + DATE() | e.g. index on `flights(origin, destination, departure_at)` with a sargable range | | e.g. 97% (40×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which write queries got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 144,792 bookings. Next year the business expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 12 CSV files with about **20× the rows** (≈ 2,896,000 bookings, ≈ 3,268,000 passengers, ≈ 1,698,000 flight bookings, ≈ 1,198,000 hotel bookings, ≈ 800,000 customers). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them could run for a very long time.
   - R22 pages with `OFFSET`; if you replaced it with keyset pagination, explain how the "last seen" value is chosen for the large data.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / customer-facing | R01, R02, R03, R04, R05, R06, R07, R10, R11, R23, W01, W02, W03 | **under 5 ms** |
| Interactive partner tools | R08, R13, R18, R22, R24, W05 | **under 250 ms** |
| Reports and analytics | R09, R12, R14, R15, R16, R17, R19, R20, R21, R25 | **under 5,000 ms** |
| Batch jobs | W04 | **under 1,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100×:** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `bookings`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** Would you shard bookings by customer, by product (flight vs hotel), or by travel date? Think about My Trips (one customer) vs manifests (one flight). Which queries become cross-shard, and how would you handle them?
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `bookings`, archiving old data, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
makemytrip-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Mon 2 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |
| Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | **CP5** Individual analysis |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

## Evaluation (40 marks)

These 40 marks are the DE part of the project: **Query Execution (10)** and **Code Optimization (30)**.
The AP project (20) and your Individual analysis (40) make up the rest of the 100.

| Phase | Criteria | Marks |
|-------|----------|------:|
| | **Query Execution** | **10** |
| 1 | Problems understood, stakeholders and query groups correctly identified | 2 |
| 2 | Correct data types (1), keys and foreign keys with justified delete rules (1), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (1), ER diagram + normal-form analysis (1), data loads cleanly + integrity checks (1) | 5 |
| 3 | All 30 queries measured with the required method: 3 runs, average (1), raw plans committed (1), scan type and reason for each query (1) | 3 |
| | **Code Optimization** | **30** |
| 4 | Speed-up achieved with appropriate techniques (6), every index justified (3), results proven unchanged (2), wrong-result query found and explained (2), write overhead and index storage reported (3) | 16 |
| 5 | Large-dataset results with all targets met or explained (4), growth analysis (3), scale-only problems found and fixed (3), partitioning DDL + sharding/replica design backed by your numbers (4) | 14 |
| | **Total** | **40** |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Flight search: Delhi → Mumbai on 5 July 2026 with seats left**
```sql
SELECT f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare,
       f.total_seats - coalesce(sum(fb.passengers) FILTER (WHERE b.status <> 'CANCELLED'), 0) AS seats_left
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
LEFT JOIN bookings b         ON b.booking_id = fb.booking_id
WHERE f.origin = 'DEL' AND f.destination = 'BOM'
  AND DATE(f.departure_at) = '2026-07-05'
  AND f.status <> 'CANCELLED'
GROUP BY f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare, f.total_seats
ORDER BY f.departure_at;
```

**R02: Fare calendar: cheapest Bengaluru → Delhi fare for each day of July 2026**
```sql
SELECT departure_at::date AS day, min(base_fare) AS cheapest_fare
FROM flights
WHERE origin = 'BLR' AND destination = 'DEL'
  AND departure_at::date BETWEEN '2026-07-01' AND '2026-07-31'
GROUP BY 1
ORDER BY 1;
```

**R03: Hotel search: 4★+ hotels in Goa with a swimming pool, best rated first**
```sql
SELECT hotel_id, hotel_name, star_rating, user_rating
FROM hotels
WHERE city_name = 'Goa'
  AND star_rating >= 4
  AND amenities ->> 'pool' = 'true'
ORDER BY user_rating DESC NULLS LAST
LIMIT 20;
```

**R04: Room availability: rooms left per room type of hotel 208 for 10–12 July 2026**
```sql
SELECT rt.room_type_id, rt.room_name, rt.price_per_night,
       rt.total_rooms - coalesce(sum(hb.rooms) FILTER (WHERE b.status <> 'CANCELLED'), 0) AS rooms_left
FROM room_types rt
LEFT JOIN hotel_bookings hb ON hb.room_type_id = rt.room_type_id
                           AND hb.check_in < '2026-07-12' AND hb.check_out > '2026-07-10'
LEFT JOIN bookings b        ON b.booking_id = hb.booking_id
WHERE rt.hotel_id = 208
GROUP BY rt.room_type_id, rt.room_name, rt.price_per_night, rt.total_rooms
ORDER BY rt.price_per_night;
```

**R05: "My Trips": customer 1021's upcoming confirmed trips**
```sql
SELECT b.booking_ref, b.booking_type, b.total_amount,
       coalesce(f.departure_at::date, hb.check_in) AS travel_date
FROM bookings b
LEFT JOIN flight_bookings fb ON fb.booking_id = b.booking_id
LEFT JOIN flights f          ON f.flight_id = fb.flight_id
LEFT JOIN hotel_bookings hb  ON hb.booking_id = b.booking_id
WHERE b.customer_id = 1021 AND b.status = 'CONFIRMED'
ORDER BY travel_date;
```

**R06: Support: open a booking by its reference**
```sql
SELECT booking_id, customer_id, booking_type, status, total_amount, booked_at
FROM bookings
WHERE booking_ref = 'MMA7772F';
```

**R07: Airline manifest: passengers on flight 13047 ordered by seat**
```sql
SELECT p.full_name, p.age, p.gender, p.seat_no, b.booking_ref
FROM flight_bookings fb
JOIN bookings b   ON b.booking_id = fb.booking_id AND b.status <> 'CANCELLED'
JOIN passengers p ON p.booking_id = fb.booking_id
WHERE fb.flight_id = 13047
ORDER BY p.seat_no NULLS LAST, p.full_name;
```

**R08: Revenue management: July 2026 flights with fewer than 5 passengers booked**
```sql
SELECT f.flight_id, f.flight_no, f.departure_at, coalesce(sum(fb.passengers), 0) AS passengers
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
WHERE f.departure_at >= '2026-07-01' AND f.status = 'SCHEDULED'
GROUP BY f.flight_id, f.flight_no, f.departure_at
HAVING coalesce(sum(fb.passengers), 0) < 5
ORDER BY f.departure_at;
```

**R09: Trends: 10 most-booked routes in June 2026**
```sql
SELECT f.origin, f.destination, count(*) AS bookings, sum(fb.passengers) AS passengers
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE b.booked_at >= '2026-06-01' AND b.booked_at < '2026-07-01'
GROUP BY f.origin, f.destination
ORDER BY bookings DESC
LIMIT 10;
```

**R10: Flight status board: delayed flights**
```sql
SELECT flight_id, flight_no, origin, destination, departure_at
FROM flights
WHERE status = 'DELAYED'
ORDER BY departure_at;
```

**R11: Payments: bookings waiting for payment for more than 30 minutes (checked at 23:59 on 30 Jun 2026)**
```sql
SELECT booking_id, booking_ref, customer_id, total_amount, booked_at
FROM bookings
WHERE status = 'PENDING_PAYMENT'
  AND booked_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '30 minutes'
ORDER BY booked_at;
```

**R12: Finance: revenue per booking type per month in 2026 (excluding cancellations)**
```sql
SELECT date_trunc('month', booked_at) AS month, booking_type, count(*) AS bookings, sum(total_amount) AS revenue
FROM bookings
WHERE status <> 'CANCELLED'
  AND EXTRACT(YEAR FROM booked_at) = 2026
GROUP BY 1, 2
ORDER BY 1, 2;
```

**R13: Marketing: coupons that have never been used**
```sql
SELECT c.coupon_code, c.applies_to, c.discount_pct
FROM coupons c
WHERE c.coupon_code NOT IN (SELECT b.coupon_code FROM bookings b);
```

**R14: Airline partnerships: cancellation rate of flight bookings per airline**
```sql
SELECT a.airline_name, count(*) AS bookings,
       round(100.0 * count(*) FILTER (WHERE b.status = 'CANCELLED') / count(*), 2) AS cancel_pct
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
JOIN airlines a         ON a.airline_code = f.airline_code
GROUP BY a.airline_name
ORDER BY cancel_pct DESC;
```

**R15: Hotel partnerships: room-nights sold per city for stays in June 2026**
```sql
SELECT h.city_name,
       sum(hb.rooms * (least(hb.check_out, DATE '2026-07-01') - greatest(hb.check_in, DATE '2026-06-01'))) AS room_nights
FROM hotel_bookings hb
JOIN hotels h   ON h.hotel_id = hb.hotel_id
JOIN bookings b ON b.booking_id = hb.booking_id AND b.status <> 'CANCELLED'
WHERE hb.check_in < '2026-07-01' AND hb.check_out > '2026-06-01'
GROUP BY h.city_name
ORDER BY room_nights DESC;
```

**R16: Insights: average days between booking and travel, per booking type and loyalty tier**
```sql
SELECT b.booking_type, c.loyalty_tier,
       round(avg(coalesce(f.departure_at::date, hb.check_in) - b.booked_at::date), 1) AS avg_lead_days
FROM bookings b
JOIN customers c ON c.customer_id = b.customer_id
LEFT JOIN flight_bookings fb ON fb.booking_id = b.booking_id
LEFT JOIN flights f          ON f.flight_id = fb.flight_id
LEFT JOIN hotel_bookings hb  ON hb.booking_id = b.booking_id
GROUP BY b.booking_type, c.loyalty_tier
ORDER BY 1, 2;
```

**R17: Loyalty: customers with 3 or more completed trips that started in 2026**
```sql
SELECT b.customer_id, count(*) AS trips, sum(b.total_amount) AS spend
FROM bookings b
WHERE b.status = 'COMPLETED'
  AND b.booked_at >= '2026-01-01'
GROUP BY b.customer_id
HAVING count(*) >= 3
ORDER BY trips DESC, spend DESC;
```

**R18: Hotel page: Goa reviews that mention breakfast**
```sql
SELECT r.review_id, h.hotel_name, r.rating, r.review_text
FROM hotel_reviews r
JOIN hotels h ON h.hotel_id = r.hotel_id
WHERE h.city_name = 'Goa'
  AND r.review_text ILIKE '%breakfast%'
ORDER BY r.created_at DESC
LIMIT 30;
```

**R19: Operations: passengers booked on every flight departing in June 2026**
```sql
SELECT f.flight_id, f.flight_no, f.departure_at,
       (SELECT count(*) FROM passengers p JOIN flight_bookings fb ON fb.booking_id = p.booking_id
         WHERE fb.flight_id = f.flight_id) AS passengers
FROM flights f
WHERE f.departure_at >= '2026-06-01' AND f.departure_at < '2026-07-01'
ORDER BY passengers DESC, f.departure_at;
```

**R20: Finance: bookings per day and running total for June 2026**
```sql
SELECT day, bookings, sum(bookings) OVER (ORDER BY day) AS running_total
FROM (
    SELECT booked_at::date AS day, count(*) AS bookings
    FROM bookings
    WHERE booked_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;
```

**R21: Concessions: senior-citizen passengers (60+) per route in 2026**
```sql
SELECT f.origin, f.destination, count(*) AS senior_passengers
FROM passengers p
JOIN flight_bookings fb ON fb.booking_id = p.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE p.age >= 60
  AND f.departure_at >= '2026-01-01'
GROUP BY f.origin, f.destination
ORDER BY senior_passengers DESC;
```

**R22: Support console: all bookings, newest first, page 4,001 (25 per page)**
```sql
SELECT booking_id, booking_ref, booking_type, status, total_amount, booked_at
FROM bookings
ORDER BY booked_at DESC
OFFSET 100000
LIMIT 25;
```

**R23: Sign-in: find the customer by email, ignoring case**
```sql
SELECT customer_id, full_name, loyalty_tier
FROM customers
WHERE lower(email) = 'siddharth.sharma1021@rediffmail.com';
```

**R24: Hotel ranking: Goa hotels with at least 5 reviews, by average review rating**
```sql
SELECT h.hotel_id, h.hotel_name, round(avg(r.rating), 2) AS avg_rating, count(*) AS reviews
FROM hotels h
JOIN hotel_reviews r ON r.hotel_id = h.hotel_id
WHERE h.city_name = 'Goa'
GROUP BY h.hotel_id, h.hotel_name
HAVING count(*) >= 5
ORDER BY avg_rating DESC, reviews DESC
LIMIT 20;
```

**R25: Insights: last-minute flight bookings (made less than 24 hours before departure) in 2026**
```sql
SELECT b.booking_id, b.booked_at, f.departure_at, f.origin, f.destination
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE f.departure_at - b.booked_at < interval '24 hours'
  AND b.booked_at >= '2026-01-01'
ORDER BY b.booked_at DESC;
```

**W01: Checkout: create a pending flight booking for customer 1021**
```sql
INSERT INTO bookings (booking_id, booking_ref, customer_id, booking_type, booked_at, total_amount, payment_method, status)
VALUES (90000001, 'MMZZ0001', 1021, 'FLIGHT', '2026-07-01 10:00:00+05:30', 5400.00, 'UPI', 'PENDING_PAYMENT');
```

**W02: Payment gateway callback: confirm the oldest booking that is waiting for payment**
```sql
UPDATE bookings
SET status = 'CONFIRMED'
WHERE booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'PENDING_PAYMENT');
```

**W03: Customer cancels booking MMA7772F with a 70% refund**
```sql
UPDATE bookings
SET status = 'CANCELLED', cancelled_at = '2026-07-01 11:00:00+05:30', refund_amount = round(total_amount * 0.7, 2)
WHERE booking_ref = 'MMA7772F' AND status <> 'CANCELLED';
```

**W04: Flight ops: every flight that was scheduled to depart before 1 July 2026 has now departed**
```sql
UPDATE flights
SET status = 'DEPARTED'
WHERE status IN ('SCHEDULED', 'DELAYED')
  AND departure_at < '2026-07-01 00:00:00+05:30';
```

**W05: Front desk: assign room numbers to every guest checking in on 1 July 2026**
```sql
UPDATE hotel_bookings hb
SET room_number = (100 + hb.booking_id % 400)::text
FROM bookings b
WHERE b.booking_id = hb.booking_id
  AND b.status = 'CONFIRMED'
  AND hb.check_in = '2026-07-01'
  AND hb.room_number IS NULL;
```
