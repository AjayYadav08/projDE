# Phase 1: Problem Understanding

## Overview
MakeMyTrip operates high-volume dual-vertical travel reservations covering scheduled passenger flights and hotel accommodations. Below is a structured analysis of problems P1 through P8 reported by business and engineering stakeholders, categorized by real-time customer-facing workflows versus asynchronous analytical reporting.

---

## Problem Analysis (P1 – P8)

| ID | Reported Issue & Business Need | Primary Stakeholder | Query Classification | Related Workload Queries |
|:---|:---|:---|:---|:---|
| **P1** | **Flight Search & Dynamic Fare Display**: High search latency and stale inventory counts degrade user conversion during active searches. The system needs low-latency retrieval of non-cancelled flights between specific origins/destinations with real-time seat availability calculation based on live bookings. | Traveller, Airline Partners, Revenue Management | Customer-Facing / Real-Time | R01, R02, R10 |
| **P2** | **Hotel Search with Amenity Filtering & Date-Range Availability**: Multi-attribute filtering (star ratings, JSON amenities like pools/gyms) and real-time room availability calculation across date intervals are bottlenecked by sequential full-table scans. Needs sub-second catalog filtering and inventory reconciliation. | Traveller, Hotel Partners | Customer-Facing / Real-Time | R03, R04, R18, R24 |
| **P3** | **Customer Account, Itinerary ("My Trips") & Support Lookup**: Customers experience high latency during sign-in, profile queries, and itinerary lookups. Customer care cannot rapidly pull reservations by reference code `booking_ref` during customer interactions. | Traveller, Customer Support | Customer-Facing / Real-Time | R05, R06, R23 |
| **P4** | **Airline Operations, Passenger Manifests & Load Monitoring**: Operational delays in extracting flight manifests, calculating cancellation rates, and isolating under-performing scheduled routes. Gate agents and airline dispatchers need fast access to passenger seat assignments and flight status transitions. | Airline Partners, Flight Operations | Real-Time Ops (R07, W04) & Reporting (R08, R14, R19) | R07, R08, R14, R19, W04 |
| **P5** | **Checkout Pipeline & Payment State Machine Transitions**: High contention and latency when polling for pending transactions (>30 min timeouts), confirming payments upon gateway webhook callbacks, and computing partial refunds upon cancellation. Needs atomic, low-overhead transaction handling. | Payments Team, Traveller | Customer-Facing / Real-Time | R11, W01, W02, W03 |
| **P6** | **Promotional Coupon Auditing ("Coupons Never Used")**: Marketing reports on unused promotional codes continuously return zero rows due to SQL three-valued logic (`NOT IN` subquery evaluating over nullable columns). Needs query correction and optimized scanning to identify dormant campaigns. | Marketing Team | Reporting / Analytics | R13 |
| **P7** | **Hotel Partner Utilization & Front-Desk Check-in Automation**: Front desk operations need batch room assignment for daily arrivals without blocking guests. Partner management requires aggregated room-night metrics per city for commercial settlements. | Hotel Partners, Front Desk Agents | Real-Time Check-In (W05) & Reporting (R15) | R15, W05 |
| **P8** | **Financial Accounting, Cohort Analytics & Scale Preparedness**: Aggregate financial reporting (monthly revenue, booking lead times, customer lifetime value, concessions, offset pagination) suffers from full table scans and memory-intensive hash joins. Needs robust query paths and partition readiness for 20× data growth. | Finance, Loyalty Team, Executive Insights | Reporting / Analytics | R09, R12, R16, R17, R20, R21, R22, R25 |

---

## Workload Classification & Performance Targets

1. **Customer-Facing / Real-Time Operations**:
   - Queries: `R01`, `R02`, `R03`, `R04`, `R05`, `R06`, `R07`, `R10`, `R11`, `R23`, `W01`, `W02`, `W03`.
   - Business Requirement: Sub-5 ms p95 response time to prevent checkout drop-offs and app lag.
2. **Interactive Partner & Operations Tools**:
   - Queries: `R08`, `R13`, `R18`, `R22`, `R24`, `W05`.
   - Business Requirement: Under 250 ms execution time for interactive operational dashboards.
3. **Internal Reporting & Analytical Insights**:
   - Queries: `R09`, `R12`, `R14`, `R15`, `R16`, `R17`, `R19`, `R20`, `R21`, `R25`.
   - Business Requirement: Under 5,000 ms; aggregations and multi-table joins optimized via covering indexes or sargable filters.
4. **Scheduled Batch Jobs**:
   - Queries: `W04`.
   - Business Requirement: Under 1,000 ms to update flight operational states without prolonged row-level locks.

---

## Architectural & Data Assumptions
1. **Single-vertical Subtyping**: A booking row in `bookings` is mutually exclusive between `FLIGHT` and `HOTEL` (`flight_bookings` and `hotel_bookings` share the primary key `booking_id`).
2. **Denormalization vs Derived Storage**: `flight_bookings.fare_paid` equals `bookings.total_amount + bookings.discount`, recording pre-discount list fare. `passengers.booking_id` maintains individual passenger details, matching the count in `flight_bookings.passengers`.
3. **Temporal Validity**: Stays and flights follow chronological sequence (`arrival_at > departure_at`, `check_out > check_in`, `cancelled_at >= booked_at`).
4. **Seat and Room Assignment Lifecycle**: Seats and room numbers are initially `NULL` upon booking creation and are assigned dynamically upon web check-in or arrival.

