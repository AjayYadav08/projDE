-- =====================================================================
-- MakeMyTrip DBMS Project: Large Dataset Data Loading Script (Phase 5)
-- Loads large_data/ (20x scale: ~2.9M bookings) in topological FK order.
-- =====================================================================

SET search_path TO mmt;

-- Level 0: Independent master tables
\copy airlines FROM 'large_data/airlines.csv' WITH (FORMAT csv, HEADER true);
\copy airports FROM 'large_data/airports.csv' WITH (FORMAT csv, HEADER true);
\copy customers FROM 'large_data/customers.csv' WITH (FORMAT csv, HEADER true);
\copy coupons FROM 'large_data/coupons.csv' WITH (FORMAT csv, HEADER true);
\copy hotels FROM 'large_data/hotels.csv' WITH (FORMAT csv, HEADER true);

-- Level 1: Tables dependent on Level 0
\copy flights FROM 'large_data/flights.csv' WITH (FORMAT csv, HEADER true);
\copy room_types FROM 'large_data/room_types.csv' WITH (FORMAT csv, HEADER true);
\copy bookings FROM 'large_data/bookings.csv' WITH (FORMAT csv, HEADER true);

-- Level 2: Specific booking subtype tables
\copy flight_bookings FROM 'large_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true);
\copy hotel_bookings FROM 'large_data/hotel_bookings.csv' WITH (FORMAT csv, HEADER true);

-- Level 3: Child line-item and review entities
\copy passengers FROM 'large_data/passengers.csv' WITH (FORMAT csv, HEADER true);
\copy hotel_reviews FROM 'large_data/hotel_reviews.csv' WITH (FORMAT csv, HEADER true);

-- Refresh optimizer statistics
ANALYZE;

