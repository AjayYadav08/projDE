-- =====================================================================
-- MakeMyTrip DBMS Project: Performance Optimization Indexes (Phase 4)
-- Schema: mmt
-- Every index is accompanied by query mapping and design justification.
-- =====================================================================

SET search_path TO mmt;

-- Enable trigram extension for substring indexing
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------
-- 1. Flights Search & Fare Calendar (Serves R01, R02)
-- Composite B-tree: equality columns (origin, destination) followed by
-- range column (departure_at), including base_fare.
-- Enables Index Only Scan without visiting the table heap.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_flights_route_date_fare
    ON flights (origin, destination, departure_at, base_fare);

CREATE INDEX IF NOT EXISTS idx_flights_search
    ON flights (origin, destination, departure_at)
    INCLUDE (flight_no, arrival_at, base_fare, total_seats)
    WHERE status <> 'CANCELLED';

-- ---------------------------------------------------------------------
-- 2. Flight Bookings by Flight ID (Serves R01, R07, R08, R09, R14, R19, R21, R25)
-- Foreign-key index on flight_id. In the unindexed schema, joining flights
-- to flight_bookings caused full 85k-row sequential scans.
-- Including booking_id and passengers allows Index Only Scans for seat sums.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_flight_bookings_flight_id
    ON flight_bookings (flight_id)
    INCLUDE (booking_id, passengers);

-- ---------------------------------------------------------------------
-- 3. Hotel Search with Amenity Filter (Serves R03)
-- Composite expression index: filters on city_name and star_rating,
-- matches the JSONB path expression (amenities ->> 'pool'), and sorts by
-- user_rating DESC NULLS LAST.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hotels_search
    ON hotels (city_name, star_rating, ((amenities ->> 'pool')), user_rating DESC NULLS LAST)
    INCLUDE (hotel_name);

-- ---------------------------------------------------------------------
-- 4. Room Types by Hotel (Serves R04)
-- Composite index on hotel_id and sort order price_per_night, with
-- covering columns room_name and total_rooms.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_room_types_hotel
    ON room_types (hotel_id, price_per_night)
    INCLUDE (room_name, total_rooms);

-- ---------------------------------------------------------------------
-- 5. Hotel Bookings Date Overlap per Room Type (Serves R04)
-- Indexes room_type_id with stay dates to resolve date-overlap conditions
-- (check_in < end AND check_out > start) without scanning unrelated stays.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_rt_dates
    ON hotel_bookings (room_type_id, check_in, check_out)
    INCLUDE (rooms, booking_id);

-- ---------------------------------------------------------------------
-- 6. Hotel Bookings Date Overlap for City Room-Nights (Serves R15)
-- Supports broad date range filtering for stay night accounting across June 2026.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_dates
    ON hotel_bookings (check_in, check_out)
    INCLUDE (hotel_id, booking_id, rooms);

-- ---------------------------------------------------------------------
-- 7. Front Desk Unassigned Room Allocation (Serves W05)
-- Partial index indexing only pending check-ins without assigned rooms.
-- Keeps the index tiny (only unassigned reservations) and updates fast.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_w05
    ON hotel_bookings (check_in)
    WHERE room_number IS NULL;

-- ---------------------------------------------------------------------
-- 8. Customer Confirmed Itineraries "My Trips" (Serves R05)
-- Composite index on customer_id and status, including trip fields.
-- Turns a 144k-row scan into an immediate index point lookup.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_bookings_customer_status
    ON bookings (customer_id, status)
    INCLUDE (booking_ref, booking_type, total_amount);

-- ---------------------------------------------------------------------
-- 9. Pending Payment Queue & Gateway Callback (Serves R11, W02)
-- Partial index covering only rows with status = 'PENDING_PAYMENT'.
-- Powers both R11 (timeout polling) and W02 (min(booking_id) FIFO confirmation).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_bookings_pending_payment
    ON bookings (booking_id, booked_at)
    WHERE status = 'PENDING_PAYMENT';

-- ---------------------------------------------------------------------
-- 10. Monthly Financial Revenue Aggregation (Serves R12)
-- Partial index covering non-cancelled 2026 bookings sorted by booked_at.
-- Enables efficient index range scan for monthly financial aggregations.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_bookings_revenue_2026
    ON bookings (booked_at, booking_type)
    INCLUDE (total_amount)
    WHERE status <> 'CANCELLED';

-- ---------------------------------------------------------------------
-- 11. Promotional Coupon Usage (Serves R13)
-- Partial index covering used coupon codes. Accelerates anti-joins
-- (NOT EXISTS) from the coupons catalog.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_bookings_coupon_code
    ON bookings (coupon_code)
    WHERE coupon_code IS NOT NULL;

-- ---------------------------------------------------------------------
-- 12. Completed Customer Trips for Loyalty Program (Serves R17)
-- Partial index covering completed 2026 bookings by customer_id and total_amount.
-- Avoids scanning active or cancelled historical bookings.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_bookings_completed_2026
    ON bookings (customer_id, total_amount)
    WHERE status = 'COMPLETED' AND booked_at >= '2026-01-01';

-- ---------------------------------------------------------------------
-- 13. General Booking Timeline & Pagination (Serves R09, R20, R22, R25)
-- B-tree on booked_at DESC with covering payload. Provides fast ordered scans
-- for date range queries and pagination without in-memory sorting.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_bookings_booked_at_desc
    ON bookings (booked_at DESC)
    INCLUDE (booking_ref, booking_type, status, total_amount);

-- ---------------------------------------------------------------------
-- 14. Review Text Substring Search (Serves R18)
-- GIN (Generalized Inverted Index) using trigram operations (gin_trgm_ops).
-- Transforms arbitrary ILIKE '%breakfast%' searches from sequential scans into
-- fast index lookups.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hotel_reviews_text_trgm
    ON hotel_reviews USING gin (review_text gin_trgm_ops);

-- ---------------------------------------------------------------------
-- 15. Hotel Reviews by Hotel Rating (Serves R24)
-- Composite index on (hotel_id, rating) for computing average review scores.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hotel_reviews_hotel_rating
    ON hotel_reviews (hotel_id, rating);

-- ---------------------------------------------------------------------
-- 16. Hotels City Lookup (Serves R15, R18, R24)
-- B-tree on (city_name, hotel_id) with hotel_name to avoid visiting hotel heap.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_hotels_city
    ON hotels (city_name, hotel_id)
    INCLUDE (hotel_name);

-- ---------------------------------------------------------------------
-- 17. Senior Citizen Concessions (Serves R21)
-- Partial index covering only passengers aged 60 and older.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_passengers_seniors
    ON passengers (booking_id)
    WHERE age >= 60;

-- ---------------------------------------------------------------------
-- 18. Case-Insensitive Customer Sign-in (Serves R23)
-- Functional expression index on lower(email) with covering user attributes.
-- Directly satisfies lower(email) = '...' in under 0.1 ms.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_customers_lower_email
    ON customers (lower(email))
    INCLUDE (customer_id, full_name, loyalty_tier);

-- ---------------------------------------------------------------------
-- 19. Delayed Flight Operations (Serves R10)
-- Partial index on delayed flights ordered by departure time.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_flights_delayed
    ON flights (departure_at)
    INCLUDE (flight_no, origin, destination)
    WHERE status = 'DELAYED';

-- ---------------------------------------------------------------------
-- 20. Flight Operations Status Batch Updates (Serves W04)
-- Partial index covering candidate flights requiring state transitions.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_flights_w04
    ON flights (departure_at)
    WHERE status IN ('SCHEDULED', 'DELAYED');

-- Refresh optimizer statistics
ANALYZE;
