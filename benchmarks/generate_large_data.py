#!/usr/bin/env python3
"""
MakeMyTrip DE Project: Deterministic 20x Large Scale Proxy Data Generator
Produces relationally valid large_data/ CSV files matching faculty specifications.
Scale:
  - customers:       800,000 rows (20x)
  - bookings:      2,895,840 rows (20x)
  - flight_bookings: 1,697,980 rows (20x)
  - hotel_bookings:  1,197,860 rows (20x)
  - passengers:    3,267,600 rows (20x)
  - hotel_reviews:   318,260 rows (20x)
  - Master tables: airlines, airports, coupons, hotels, room_types, flights
"""

import os
import sys
import csv
import time
import shutil

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SEED_DIR = os.path.join(ROOT, "seed_data")
LARGE_DIR = os.path.join(ROOT, "large_data")

SCALE_FACTOR = 20
CUST_STRIDE = 50000       # max seed customer_id is 40,000
BOOKING_STRIDE = 200000   # max seed booking_id is 150,000
REVIEW_STRIDE = 20000     # max seed review_id is 15,913

def scale_dataset():
    t_start = time.time()
    print(f"=====================================================================")
    print(f"Generating Deterministic {SCALE_FACTOR}x Large Proxy Dataset")
    print(f"Source: {SEED_DIR}")
    print(f"Target: {LARGE_DIR}")
    print(f"=====================================================================")

    if not os.path.exists(SEED_DIR):
        print(f"❌ Error: {SEED_DIR} not found.")
        sys.exit(1)

    os.makedirs(LARGE_DIR, exist_ok=True)

    # 1. Master tables: Copy directly
    master_tables = [
        "airlines.csv",
        "airports.csv",
        "coupons.csv",
        "hotels.csv",
        "room_types.csv",
        "flights.csv"
    ]
    for table in master_tables:
        src = os.path.join(SEED_DIR, table)
        dst = os.path.join(LARGE_DIR, table)
        shutil.copyfile(src, dst)
        with open(dst, 'r') as f:
            count = sum(1 for _ in f) - 1
        print(f"✔ Copied master table {table:18s} ({count:,} rows)")

    # 2. Customers (40,000 -> 800,000)
    print(f"Generating customers.csv ({40000 * SCALE_FACTOR:,} rows)...", end="", flush=True)
    t0 = time.time()
    with open(os.path.join(SEED_DIR, "customers.csv"), "r", newline="") as f_in:
        reader = list(csv.reader(f_in))
    c_header, c_rows = reader[0], reader[1:]

    with open(os.path.join(LARGE_DIR, "customers.csv"), "w", newline="") as f_out:
        writer = csv.writer(f_out)
        writer.writerow(c_header)
        for c in range(SCALE_FACTOR):
            for row in c_rows:
                cid = int(row[0]) + c * CUST_STRIDE
                name = row[1]
                email_raw = row[2]
                phone_raw = row[3]
                tier = row[4]
                created = row[5]

                if c == 0:
                    email = email_raw
                    phone = phone_raw
                else:
                    parts = email_raw.split("@")
                    email = f"{parts[0]}.u{c}@{parts[1]}"
                    phone = str(8800000000 + cid)

                writer.writerow([cid, name, email, phone, tier, created])
    print(f" done ({time.time() - t0:.2f}s)")

    # 3. Bookings (144,792 -> 2,895,840)
    print(f"Generating bookings.csv ({144792 * SCALE_FACTOR:,} rows)...", end="", flush=True)
    t0 = time.time()
    with open(os.path.join(SEED_DIR, "bookings.csv"), "r", newline="") as f_in:
        reader = list(csv.reader(f_in))
    b_header, b_rows = reader[0], reader[1:]

    with open(os.path.join(LARGE_DIR, "bookings.csv"), "w", newline="") as f_out:
        writer = csv.writer(f_out)
        writer.writerow(b_header)
        for c in range(SCALE_FACTOR):
            for row in b_rows:
                bid = int(row[0]) + c * BOOKING_STRIDE
                bref = row[1] if c == 0 else f"L{c:02d}{int(row[0]):06X}"
                cid = int(row[2]) + c * CUST_STRIDE
                writer.writerow([bid, bref, cid] + row[3:])
    print(f" done ({time.time() - t0:.2f}s)")

    # 4. Flight Bookings (84,899 -> 1,697,980)
    print(f"Generating flight_bookings.csv ({84899 * SCALE_FACTOR:,} rows)...", end="", flush=True)
    t0 = time.time()
    with open(os.path.join(SEED_DIR, "flight_bookings.csv"), "r", newline="") as f_in:
        reader = list(csv.reader(f_in))
    fb_header, fb_rows = reader[0], reader[1:]

    with open(os.path.join(LARGE_DIR, "flight_bookings.csv"), "w", newline="") as f_out:
        writer = csv.writer(f_out)
        writer.writerow(fb_header)
        for c in range(SCALE_FACTOR):
            for row in fb_rows:
                bid = int(row[0]) + c * BOOKING_STRIDE
                writer.writerow([bid] + row[1:])
    print(f" done ({time.time() - t0:.2f}s)")

    # 5. Hotel Bookings (59,893 -> 1,197,860)
    print(f"Generating hotel_bookings.csv ({59893 * SCALE_FACTOR:,} rows)...", end="", flush=True)
    t0 = time.time()
    with open(os.path.join(SEED_DIR, "hotel_bookings.csv"), "r", newline="") as f_in:
        reader = list(csv.reader(f_in))
    hb_header, hb_rows = reader[0], reader[1:]

    with open(os.path.join(LARGE_DIR, "hotel_bookings.csv"), "w", newline="") as f_out:
        writer = csv.writer(f_out)
        writer.writerow(hb_header)
        for c in range(SCALE_FACTOR):
            for row in hb_rows:
                bid = int(row[0]) + c * BOOKING_STRIDE
                writer.writerow([bid] + row[1:])
    print(f" done ({time.time() - t0:.2f}s)")

    # 6. Passengers (163,380 -> 3,267,600)
    print(f"Generating passengers.csv ({163380 * SCALE_FACTOR:,} rows)...", end="", flush=True)
    t0 = time.time()
    with open(os.path.join(SEED_DIR, "passengers.csv"), "r", newline="") as f_in:
        reader = list(csv.reader(f_in))
    p_header, p_rows = reader[0], reader[1:]

    with open(os.path.join(LARGE_DIR, "passengers.csv"), "w", newline="") as f_out:
        writer = csv.writer(f_out)
        writer.writerow(p_header)
        for c in range(SCALE_FACTOR):
            for row in p_rows:
                bid = int(row[0]) + c * BOOKING_STRIDE
                writer.writerow([bid] + row[1:])
    print(f" done ({time.time() - t0:.2f}s)")

    # 7. Hotel Reviews (15,913 -> 318,260)
    print(f"Generating hotel_reviews.csv ({15913 * SCALE_FACTOR:,} rows)...", end="", flush=True)
    t0 = time.time()
    with open(os.path.join(SEED_DIR, "hotel_reviews.csv"), "r", newline="") as f_in:
        reader = list(csv.reader(f_in))
    hr_header, hr_rows = reader[0], reader[1:]

    with open(os.path.join(LARGE_DIR, "hotel_reviews.csv"), "w", newline="") as f_out:
        writer = csv.writer(f_out)
        writer.writerow(hr_header)
        for c in range(SCALE_FACTOR):
            for row in hr_rows:
                rid = int(row[0]) + c * REVIEW_STRIDE
                bid = int(row[1]) + c * BOOKING_STRIDE
                writer.writerow([rid, bid] + row[2:])
    print(f" done ({time.time() - t0:.2f}s)")

    print(f"=====================================================================")
    print(f"✅ Large proxy dataset generated successfully in {time.time() - t_start:.2f}s!")
    print(f"=====================================================================")

if __name__ == "__main__":
    scale_dataset()
