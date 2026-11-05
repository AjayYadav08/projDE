-- =====================================================================
-- MakeMyTrip DBMS Project: Database Schema Definition (Phase 2)
-- Database: PostgreSQL 15+
-- Schema: mmt
-- Constraints only: PK, FK, UNIQUE, NOT NULL, CHECK
-- No secondary indexes are created in this file.
-- =====================================================================

DROP SCHEMA IF EXISTS mmt CASCADE;
CREATE SCHEMA mmt;
SET search_path TO mmt;

-- ---------------------------------------------------------------------
-- 1. Table: airlines
-- ---------------------------------------------------------------------
CREATE TABLE airlines (
    airline_code VARCHAR(2) PRIMARY KEY,
    airline_name VARCHAR(100) NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- 2. Table: airports
-- ---------------------------------------------------------------------
CREATE TABLE airports (
    iata_code CHAR(3) PRIMARY KEY,
    airport_name VARCHAR(150) NOT NULL,
    city_name VARCHAR(100) NOT NULL,
    country_code CHAR(2) NOT NULL
);

-- ---------------------------------------------------------------------
-- 3. Table: flights
-- ---------------------------------------------------------------------
CREATE TABLE flights (
    flight_id INT PRIMARY KEY,
    airline_code VARCHAR(2) NOT NULL REFERENCES airlines(airline_code) ON DELETE RESTRICT,
    flight_no VARCHAR(10) NOT NULL,
    origin CHAR(3) NOT NULL REFERENCES airports(iata_code) ON DELETE RESTRICT,
    destination CHAR(3) NOT NULL REFERENCES airports(iata_code) ON DELETE RESTRICT,
    departure_at TIMESTAMPTZ NOT NULL,
    arrival_at TIMESTAMPTZ NOT NULL,
    aircraft VARCHAR(50) NOT NULL,
    total_seats INT NOT NULL,
    base_fare NUMERIC(10,2) NOT NULL,
    status VARCHAR(20) NOT NULL,
    CONSTRAINT chk_flights_schedule CHECK (arrival_at > departure_at),
    CONSTRAINT chk_flights_route CHECK (origin <> destination),
    CONSTRAINT chk_flights_seats CHECK (total_seats > 0),
    CONSTRAINT chk_flights_base_fare CHECK (base_fare >= 0),
    CONSTRAINT chk_flights_status CHECK (status IN ('SCHEDULED', 'DELAYED', 'DEPARTED', 'LANDED', 'CANCELLED'))
);

-- ---------------------------------------------------------------------
-- 4. Table: hotels
-- ---------------------------------------------------------------------
CREATE TABLE hotels (
    hotel_id INT PRIMARY KEY,
    hotel_name VARCHAR(150) NOT NULL,
    city_name VARCHAR(100) NOT NULL,
    star_rating INT NOT NULL,
    user_rating NUMERIC(3,1),
    amenities JSONB NOT NULL,
    check_in_time TIME NOT NULL,
    check_out_time TIME NOT NULL,
    CONSTRAINT chk_hotels_star_rating CHECK (star_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_hotels_user_rating CHECK (user_rating IS NULL OR (user_rating >= 1.0 AND user_rating <= 5.0))
);

-- ---------------------------------------------------------------------
-- 5. Table: room_types
-- ---------------------------------------------------------------------
CREATE TABLE room_types (
    room_type_id INT PRIMARY KEY,
    hotel_id INT NOT NULL REFERENCES hotels(hotel_id) ON DELETE CASCADE,
    room_name VARCHAR(100) NOT NULL,
    max_guests INT NOT NULL,
    price_per_night NUMERIC(10,2) NOT NULL,
    total_rooms INT NOT NULL,
    CONSTRAINT chk_room_types_max_guests CHECK (max_guests > 0),
    CONSTRAINT chk_room_types_price CHECK (price_per_night >= 0),
    CONSTRAINT chk_room_types_total_rooms CHECK (total_rooms > 0)
);

-- ---------------------------------------------------------------------
-- 6. Table: customers
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL UNIQUE,
    loyalty_tier VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_customers_loyalty CHECK (loyalty_tier IN ('BLUE', 'SILVER', 'GOLD', 'PLATINUM'))
);

-- ---------------------------------------------------------------------
-- 7. Table: coupons
-- ---------------------------------------------------------------------
CREATE TABLE coupons (
    coupon_code VARCHAR(30) PRIMARY KEY,
    applies_to VARCHAR(20) NOT NULL,
    discount_pct NUMERIC(5,2) NOT NULL,
    max_discount NUMERIC(10,2) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    CONSTRAINT chk_coupons_applies_to CHECK (applies_to IN ('HOTEL', 'FLIGHT', 'ALL')),
    CONSTRAINT chk_coupons_discount_pct CHECK (discount_pct > 0 AND discount_pct <= 100),
    CONSTRAINT chk_coupons_max_discount CHECK (max_discount > 0),
    CONSTRAINT chk_coupons_validity CHECK (valid_to >= valid_from)
);

-- ---------------------------------------------------------------------
-- 8. Table: bookings
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
    booking_id INT PRIMARY KEY,
    booking_ref VARCHAR(20) NOT NULL UNIQUE,
    customer_id INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    booking_type VARCHAR(10) NOT NULL,
    booked_at TIMESTAMPTZ NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    coupon_code VARCHAR(30) REFERENCES coupons(coupon_code) ON DELETE SET NULL,
    discount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    payment_method VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    cancelled_at TIMESTAMPTZ,
    refund_amount NUMERIC(10,2),
    CONSTRAINT chk_bookings_type CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    CONSTRAINT chk_bookings_payment_method CHECK (payment_method IN ('CARD', 'NETBANKING', 'UPI', 'WALLET', 'EMI')),
    CONSTRAINT chk_bookings_status CHECK (status IN ('CONFIRMED', 'COMPLETED', 'CANCELLED', 'PENDING_PAYMENT')),
    CONSTRAINT chk_bookings_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_bookings_discount CHECK (discount >= 0),
    CONSTRAINT chk_bookings_cancellation CHECK (
        (status = 'CANCELLED' AND cancelled_at IS NOT NULL AND refund_amount IS NOT NULL) OR
        (status <> 'CANCELLED' AND cancelled_at IS NULL AND refund_amount IS NULL)
    ),
    CONSTRAINT chk_bookings_refund CHECK (refund_amount IS NULL OR refund_amount <= total_amount),
    CONSTRAINT chk_bookings_coupon_discount CHECK (
        (discount = 0.00) OR (discount > 0.00 AND coupon_code IS NOT NULL)
    )
);

-- ---------------------------------------------------------------------
-- 9. Table: flight_bookings
-- ---------------------------------------------------------------------
CREATE TABLE flight_bookings (
    booking_id INT PRIMARY KEY REFERENCES bookings(booking_id) ON DELETE CASCADE,
    flight_id INT NOT NULL REFERENCES flights(flight_id) ON DELETE RESTRICT,
    cabin VARCHAR(20) NOT NULL,
    passengers INT NOT NULL,
    fare_paid NUMERIC(10,2) NOT NULL,
    CONSTRAINT chk_flight_bookings_cabin CHECK (cabin IN ('ECONOMY', 'PREMIUM', 'BUSINESS')),
    CONSTRAINT chk_flight_bookings_passengers CHECK (passengers > 0),
    CONSTRAINT chk_flight_bookings_fare CHECK (fare_paid >= 0)
);

-- ---------------------------------------------------------------------
-- 10. Table: passengers
-- ---------------------------------------------------------------------
CREATE TABLE passengers (
    booking_id INT NOT NULL REFERENCES flight_bookings(booking_id) ON DELETE CASCADE,
    seq_no INT NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    age INT NOT NULL,
    gender CHAR(1) NOT NULL,
    seat_no VARCHAR(10),
    PRIMARY KEY (booking_id, seq_no),
    CONSTRAINT chk_passengers_seq CHECK (seq_no > 0),
    CONSTRAINT chk_passengers_age CHECK (age >= 0 AND age <= 120),
    CONSTRAINT chk_passengers_gender CHECK (gender IN ('M', 'F', 'X'))
);

-- ---------------------------------------------------------------------
-- 11. Table: hotel_bookings
-- ---------------------------------------------------------------------
CREATE TABLE hotel_bookings (
    booking_id INT PRIMARY KEY REFERENCES bookings(booking_id) ON DELETE CASCADE,
    hotel_id INT NOT NULL REFERENCES hotels(hotel_id) ON DELETE RESTRICT,
    room_type_id INT NOT NULL REFERENCES room_types(room_type_id) ON DELETE RESTRICT,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    rooms INT NOT NULL,
    guests INT NOT NULL,
    room_number VARCHAR(20),
    CONSTRAINT chk_hotel_bookings_dates CHECK (check_out > check_in),
    CONSTRAINT chk_hotel_bookings_rooms CHECK (rooms > 0),
    CONSTRAINT chk_hotel_bookings_guests CHECK (guests > 0)
);

-- ---------------------------------------------------------------------
-- 12. Table: hotel_reviews
-- ---------------------------------------------------------------------
CREATE TABLE hotel_reviews (
    review_id INT PRIMARY KEY,
    booking_id INT NOT NULL UNIQUE REFERENCES hotel_bookings(booking_id) ON DELETE CASCADE,
    hotel_id INT NOT NULL REFERENCES hotels(hotel_id) ON DELETE CASCADE,
    rating INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    review_text TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_hotel_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);
