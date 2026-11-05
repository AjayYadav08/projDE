-- =====================================================================
-- MakeMyTrip DBMS Project: Data Loading Script (Phase 2)
-- Loads seed data in strict foreign-key dependency order
-- =====================================================================

SET search_path TO mmt;

-- Level 0: Independent master tables
\copy airlines FROM 'seed_data/airlines.csv' WITH (FORMAT csv, HEADER true);
\copy airports FROM 'seed_data/airports.csv' WITH (FORMAT csv, HEADER true);
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true);
\copy coupons FROM 'seed_data/coupons.csv' WITH (FORMAT csv, HEADER true);
\copy hotels FROM 'seed_data/hotels.csv' WITH (FORMAT csv, HEADER true);

-- Level 1: Tables dependent on Level 0
\copy flights FROM 'seed_data/flights.csv' WITH (FORMAT csv, HEADER true);
\copy room_types FROM 'seed_data/room_types.csv' WITH (FORMAT csv, HEADER true);
\copy bookings FROM 'seed_data/bookings.csv' WITH (FORMAT csv, HEADER true);

-- Level 2: Specific booking subtype tables
\copy flight_bookings FROM 'seed_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true);
\copy hotel_bookings FROM 'seed_data/hotel_bookings.csv' WITH (FORMAT csv, HEADER true);

-- Level 3: Child line-item and review entities
\copy passengers FROM 'seed_data/passengers.csv' WITH (FORMAT csv, HEADER true);
\copy hotel_reviews FROM 'seed_data/hotel_reviews.csv' WITH (FORMAT csv, HEADER true);

-- Refresh optimizer statistics
ANALYZE;
