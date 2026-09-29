-- ============================================================================
-- E-COMMERCE & MULTI-CHANNEL BOOKING PERFORMANCE ANALYTICS
-- Database Dialect: PostgreSQL & MySQL 8.0+ Optimized
-- ============================================================================

-- ============================================================================
-- 1. SCHEMA DEFINITIONS & PERFORMANCE INDEXING (DDL)
-- ============================================================================

-- PostgreSQL / MySQL DDL for Star Schema
CREATE TABLE IF NOT EXISTS customers (
    customer_id VARCHAR(32) PRIMARY KEY,
    signup_date DATE NOT NULL,
    region VARCHAR(50) NOT NULL,
    channel VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS marketing_campaigns (
    campaign_id VARCHAR(32) PRIMARY KEY,
    campaign_name VARCHAR(100) NOT NULL,
    discount_code VARCHAR(50) NOT NULL,
    channel VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS bookings (
    booking_id VARCHAR(32) PRIMARY KEY,
    customer_id VARCHAR(32) NOT NULL,
    booking_date DATE NOT NULL,
    service_type VARCHAR(20) NOT NULL,
    gross_booking_value DECIMAL(10, 2) NOT NULL,
    discount_applied DECIMAL(10, 2) DEFAULT 0.00,
    payment_method VARCHAR(50),
    booking_status VARCHAR(20) NOT NULL,
    campaign_id VARCHAR(32),
    CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_campaign FOREIGN KEY (campaign_id) REFERENCES marketing_campaigns(campaign_id)
);

-- Performance Indexes for Analytical Window Functions & Joins
CREATE INDEX IF NOT EXISTS idx_bookings_cust_date ON bookings(customer_id, booking_date);
CREATE INDEX IF NOT EXISTS idx_bookings_service_date ON bookings(service_type, booking_date);
CREATE INDEX IF NOT EXISTS idx_bookings_status_date ON bookings(booking_status, booking_date);
CREATE INDEX IF NOT EXISTS idx_customers_signup ON customers(signup_date, channel);


-- ============================================================================
-- QUERY 1: RUNNING TOTAL REVENUE & MONTH-OVER-MONTH (MoM) GROWTH PARTITIONED BY SERVICE TYPE
-- ============================================================================
-- Computes completed net revenue, running cumulative revenue, and MoM growth %
-- partitioned by service type (Flight, Hotel, Bus).

-- --- PostgreSQL Version ---
WITH MonthlyServiceRevenue AS (
    SELECT 
        b.service_type,
        DATE_TRUNC('month', b.booking_date)::DATE AS booking_month,
        TO_CHAR(b.booking_date, 'YYYY-MM') AS year_month_label,
        COUNT(b.booking_id) AS total_bookings_count,
        COUNT(CASE WHEN b.booking_status = 'Completed' THEN 1 END) AS completed_bookings_count,
        ROUND(SUM(b.gross_booking_value), 2) AS total_gross_booking_value,
        -- Net Revenue recognized for Completed bookings (Gross - Discount)
        ROUND(SUM(CASE 
            WHEN b.booking_status = 'Completed' 
            THEN b.gross_booking_value - COALESCE(b.discount_applied, 0.00) 
            ELSE 0.00 
        END), 2) AS net_completed_revenue
    FROM bookings b
    GROUP BY b.service_type, DATE_TRUNC('month', b.booking_date), TO_CHAR(b.booking_date, 'YYYY-MM')
),
ServiceRevenueWithWindows AS (
    SELECT 
        service_type,
        booking_month,
        year_month_label,
        total_bookings_count,
        completed_bookings_count,
        net_completed_revenue,
        -- Running Total Revenue partitioned by service type over time
        SUM(net_completed_revenue) OVER (
            PARTITION BY service_type 
            ORDER BY booking_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_total_revenue,
        -- Prior Month Revenue partitioned by service type
        LAG(net_completed_revenue, 1) OVER (
            PARTITION BY service_type 
            ORDER BY booking_month
        ) AS prior_month_revenue
    FROM MonthlyServiceRevenue
)
SELECT 
    service_type,
    year_month_label AS period,
    net_completed_revenue,
    running_total_revenue,
    prior_month_revenue,
    -- Month-over-Month Growth %: ((Current - Prior) / Prior) * 100
    ROUND(
        CASE 
            WHEN prior_month_revenue IS NULL OR prior_month_revenue = 0 THEN NULL
            ELSE ((net_completed_revenue - prior_month_revenue) * 100.0) / prior_month_revenue
        END, 
        2
    ) AS mom_revenue_growth_pct
FROM ServiceRevenueWithWindows
ORDER BY service_type, booking_month;

/*
-- --- MySQL 8.0+ Equivalent for Query 1 ---
WITH MonthlyServiceRevenue AS (
    SELECT 
        b.service_type,
        DATE_FORMAT(b.booking_date, '%Y-%m-01') AS booking_month,
        DATE_FORMAT(b.booking_date, '%Y-%m') AS year_month_label,
        COUNT(b.booking_id) AS total_bookings_count,
        COUNT(CASE WHEN b.booking_status = 'Completed' THEN 1 END) AS completed_bookings_count,
        ROUND(SUM(b.gross_booking_value), 2) AS total_gross_booking_value,
        ROUND(SUM(CASE 
            WHEN b.booking_status = 'Completed' 
            THEN b.gross_booking_value - COALESCE(b.discount_applied, 0.00) 
            ELSE 0.00 
        END), 2) AS net_completed_revenue
    FROM bookings b
    GROUP BY b.service_type, DATE_FORMAT(b.booking_date, '%Y-%m-01'), DATE_FORMAT(b.booking_date, '%Y-%m')
),
ServiceRevenueWithWindows AS (
    SELECT 
        service_type,
        booking_month,
        year_month_label,
        total_bookings_count,
        completed_bookings_count,
        net_completed_revenue,
        SUM(net_completed_revenue) OVER (
            PARTITION BY service_type 
            ORDER BY booking_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_total_revenue,
        LAG(net_completed_revenue, 1) OVER (
            PARTITION BY service_type 
            ORDER BY booking_month
        ) AS prior_month_revenue
    FROM MonthlyServiceRevenue
)
SELECT 
    service_type,
    year_month_label AS period,
    net_completed_revenue,
    running_total_revenue,
    prior_month_revenue,
    ROUND(
        CASE 
            WHEN prior_month_revenue IS NULL OR prior_month_revenue = 0 THEN NULL
            ELSE ((net_completed_revenue - prior_month_revenue) * 100.0) / prior_month_revenue
        END, 
        2
    ) AS mom_revenue_growth_pct
FROM ServiceRevenueWithWindows
ORDER BY service_type, booking_month;
*/


-- ============================================================================
-- QUERY 2: USER PURCHASE FREQUENCY, DENSE_RANK() SPEND, AND REPEAT BOOKING RATE
-- ============================================================================
-- Part A: Customer Purchase Frequency & Customer Gross Spend Ranking using DENSE_RANK()
WITH CustomerSpendAggregates AS (
    SELECT 
        c.customer_id,
        c.region,
        c.channel AS acquisition_channel,
        c.signup_date,
        COUNT(b.booking_id) AS total_bookings,
        COUNT(CASE WHEN b.booking_status = 'Completed' THEN 1 END) AS completed_bookings,
        ROUND(SUM(b.gross_booking_value), 2) AS total_gross_spend,
        ROUND(SUM(b.gross_booking_value - COALESCE(b.discount_applied, 0.00)), 2) AS total_net_spend,
        MIN(b.booking_date) AS first_booking_date,
        MAX(b.booking_date) AS last_booking_date
    FROM customers c
    INNER JOIN bookings b ON c.customer_id = b.customer_id
    GROUP BY c.customer_id, c.region, c.channel, c.signup_date
)
SELECT 
    customer_id,
    region,
    acquisition_channel,
    signup_date,
    total_bookings,
    completed_bookings,
    total_gross_spend,
    total_net_spend,
    first_booking_date,
    last_booking_date,
    -- Frequency Tier Classification
    CASE 
        WHEN total_bookings = 1 THEN '1. One-Time Booker'
        WHEN total_bookings BETWEEN 2 AND 3 THEN '2. Occasional Booker (2-3)'
        WHEN total_bookings BETWEEN 4 AND 6 THEN '3. Frequent Booker (4-6)'
        ELSE '4. VIP / High-Frequency (7+)'
    END AS purchase_frequency_segment,
    -- DENSE_RANK() customer ranking based on gross booking spend
    DENSE_RANK() OVER (ORDER BY total_gross_spend DESC) AS gross_spend_rank
FROM CustomerSpendAggregates
ORDER BY gross_spend_rank ASC;

-- Part B: Repeat Booking Rate Computation (Channel Breakdown + Executive Total)
WITH CustomerBookingSummary AS (
    SELECT 
        c.customer_id,
        c.channel AS acquisition_channel,
        COUNT(b.booking_id) AS lifetime_booking_count
    FROM customers c
    INNER JOIN bookings b ON c.customer_id = b.customer_id
    GROUP BY c.customer_id, c.channel
)
SELECT 
    acquisition_channel,
    COUNT(customer_id) AS total_acquired_customers,
    COUNT(CASE WHEN lifetime_booking_count = 1 THEN 1 END) AS single_booking_customers,
    COUNT(CASE WHEN lifetime_booking_count > 1 THEN 1 END) AS repeat_booking_customers,
    -- Repeat Booking Rate (%) = (Repeat Customers / Total Customers) * 100
    ROUND(
        COUNT(CASE WHEN lifetime_booking_count > 1 THEN 1 END) * 100.0 / COUNT(customer_id), 
        2
    ) AS repeat_booking_rate_pct
FROM CustomerBookingSummary
GROUP BY acquisition_channel

UNION ALL

SELECT 
    '-- EXECUTIVE TOTAL --' AS acquisition_channel,
    COUNT(customer_id) AS total_acquired_customers,
    COUNT(CASE WHEN lifetime_booking_count = 1 THEN 1 END) AS single_booking_customers,
    COUNT(CASE WHEN lifetime_booking_count > 1 THEN 1 END) AS repeat_booking_customers,
    ROUND(
        COUNT(CASE WHEN lifetime_booking_count > 1 THEN 1 END) * 100.0 / COUNT(customer_id), 
        2
    ) AS repeat_booking_rate_pct
FROM CustomerBookingSummary
ORDER BY total_acquired_customers DESC;


-- ============================================================================
-- QUERY 3: DATA CLEANING, NULL STANDARDIZATION, ORPHAN FILTERING & FLAT VIEW
-- ============================================================================
-- Standardizes nulls, filters out orphaned foreign key records, calculates
-- customer lifecycle sequences, and outputs an analytics-ready flat dataset.

CREATE OR REPLACE VIEW v_analytics_flat_bookings AS
WITH CustomerBookingSequence AS (
    SELECT 
        b.booking_id,
        b.customer_id,
        b.booking_date,
        -- Sequence number of booking per customer
        ROW_NUMBER() OVER (
            PARTITION BY b.customer_id 
            ORDER BY b.booking_date ASC, b.booking_id ASC
        ) AS customer_booking_sequence
    FROM bookings b
    -- Inner join eliminates orphaned booking records with non-existent customers
    INNER JOIN customers c ON b.customer_id = c.customer_id
)
SELECT 
    -- Fact Identifiers & Timestamps
    b.booking_id,
    b.customer_id,
    b.booking_date,
    TO_CHAR(b.booking_date, 'YYYY-MM') AS booking_year_month,
    EXTRACT(YEAR FROM b.booking_date) AS booking_year,
    EXTRACT(MONTH FROM b.booking_date) AS booking_month_num,
    TO_CHAR(b.booking_date, 'Day') AS booking_day_name,
    
    -- Transactional Dimensions
    UPPER(TRIM(b.service_type)) AS service_type,
    TRIM(b.booking_status) AS booking_status,
    COALESCE(NULLIF(TRIM(b.payment_method), ''), 'Unspecified') AS payment_method,

    -- Financial Measures & Null Handling
    ROUND(b.gross_booking_value, 2) AS gross_booking_value,
    ROUND(COALESCE(b.discount_applied, 0.00), 2) AS discount_applied,
    ROUND(b.gross_booking_value - COALESCE(b.discount_applied, 0.00), 2) AS net_booking_value,
    ROUND(
        CASE 
            WHEN b.gross_booking_value > 0 THEN (COALESCE(b.discount_applied, 0.00) / b.gross_booking_value) * 100.0
            ELSE 0.00 
        END, 
        2
    ) AS discount_percentage,

    -- Customer Dimensions & Cohorts
    c.signup_date,
    TO_CHAR(c.signup_date, 'YYYY-MM') AS customer_cohort_month,
    TRIM(c.region) AS customer_region,
    TRIM(c.channel) AS customer_acquisition_channel,
    
    -- Customer Retention & Lifecycle Behavioral Flags
    (b.booking_date - c.signup_date) AS days_since_signup,
    cbs.customer_booking_sequence,
    CASE WHEN cbs.customer_booking_sequence > 1 THEN 1 ELSE 0 END AS is_repeat_booking,

    -- Marketing Campaign Attribution
    COALESCE(m.campaign_id, 'DIRECT') AS campaign_id,
    COALESCE(m.campaign_name, 'Direct / Organic Traffic') AS campaign_name,
    COALESCE(m.discount_code, 'NONE') AS discount_code,
    COALESCE(m.channel, c.channel) AS campaign_channel

FROM bookings b
-- Filter orphaned booking records (strict integrity check)
INNER JOIN customers c ON b.customer_id = c.customer_id
-- Window sequence lookup
INNER JOIN CustomerBookingSequence cbs ON b.booking_id = cbs.booking_id
-- Left join campaign dimension with null coalescing
LEFT JOIN marketing_campaigns m ON b.campaign_id = m.campaign_id;
