# Multi-Channel E-Commerce & Booking Performance Analytics

[![Python 3.11](https://img.shields.io/badge/Python-3.11-3776AB.svg?style=flat&logo=python&logoColor=white)](https://python.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-336791.svg?style=flat&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![MySQL](https://img.shields.io/badge/MySQL-8.0+-4479A1.svg?style=flat&logo=mysql&logoColor=white)](https://www.mysql.com/)
[![Power BI](https://img.shields.io/badge/Power_BI-DAX_Modeling-F2C811.svg?style=flat&logo=powerbi&logoColor=black)](https://powerbi.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

An enterprise-grade, end-to-end analytics project delivering synthetic data generation, relational schema design, advanced SQL window transformations, and production-ready Power BI DAX measures for multi-channel e-commerce and booking platforms (Flights, Hotels, Buses).

---

## Architecture Overview

```
                      +---------------------------------------+
                      |       Python Data Generation          |
                      |   (100k transactions, Faker, NumPy)   |
                      +-------------------+-------------------+
                                          |
                                          v
                      +---------------------------------------+
                      |         Relational Data Store         |
                      |   (PostgreSQL / MySQL / SQLite 3)     |
                      +-------------------+-------------------+
                                          |
                                          v
                      +---------------------------------------+
                      |     Advanced SQL Transformation       |
                      |  (CTEs, Window Functions, DENSE_RANK) |
                      +-------------------+-------------------+
                                          |
                                          v
                      +---------------------------------------+
                      |        Power BI Tabular Model         |
                      |  (Star Schema, Cohort CLV, Funnel)    |
                      +---------------------------------------+
```

---

## Data Schema & Simulation Features

The synthetic data generator (`generate_dataset.py`) produces **100,000 transactions** across **35,000 customers** over a 24-month horizon (2023–2024), realistically capturing empirical booking phenomena:

### 1. Relational Entities
- **`Customers`**: `customer_id`, `signup_date`, `region` (North America, Europe, Asia-Pacific, Latin America, Middle East), `channel` (Organic, Paid Search, Social, Referral).
- **`Bookings`**: `booking_id`, `customer_id`, `booking_date`, `service_type` (Flight, Hotel, Bus), `gross_booking_value`, `discount_applied`, `payment_method`, `booking_status` (Completed, Cancelled, Refunded), `campaign_id`.
- **`Marketing_Campaigns`**: `campaign_id`, `campaign_name`, `discount_code`, `channel`.

### 2. Statistical & Behavioral Modeling
- **Seasonality & Growth**: Replicates real-world travel curves with summer vacation spikes (June: 1.35x, July: 1.45x), year-end holiday surges (Nov: 1.20x, Dec: 1.40x), post-holiday dips (Jan: 0.75x, Feb: 0.80x), and a +12% annual compounding growth rate.
- **Pareto Repeat Purchase**: Implements a discrete power-law distribution where **~35% repeat bookers generate ~77% of all booking volume**. Strictly enforces `booking_date >= signup_date`.
- **Service Cancellation Dynamics**:
  - **Flight** (45% share): Gross Booking Value log-normal ($\mu=\$380, \sigma=\$180$), cancellation rate ~13%, refund rate ~5%, completed ~82%.
  - **Hotel** (35% share): Gross Booking Value log-normal ($\mu=\$290, \sigma=\$210$), cancellation rate ~22% (reflecting free-cancellation policies), refund rate ~7%, completed ~71%.
  - **Bus** (20% share): Gross Booking Value gamma distributed ($\mu=\$45, \sigma=\$20$), cancellation rate ~7%, refund rate ~2%, completed ~91%.
- **Data Quality Injections**: Includes 40 orphaned customer IDs, 60 null payment methods, and 80 unpopulated discounts to test upstream data cleansing robustness.

---

## SQL Analytics & Transformations

All queries are documented in [`ecommerce_analytics_queries.sql`](ecommerce_analytics_queries.sql) and optimized for PostgreSQL and MySQL 8.0+:

1. **Running Total Revenue & MoM Growth**:
   - Computes completed net revenue (`gross_booking_value - discount_applied`).
   - Utilizes `SUM() OVER (PARTITION BY service_type ORDER BY booking_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)` for cumulative revenue.
   - Calculates month-over-month growth percentage using `LAG()` with division-by-zero safeguards.

2. **Customer Segmentation, `DENSE_RANK()` Spend, & Repeat Rates**:
   - Classifies customer frequency into tiers: *One-Time Booker (1)*, *Occasional Booker (2-3)*, *Frequent Booker (4-6)*, and *VIP / High-Frequency (7+)*.
   - Ranks customers by gross spend using `DENSE_RANK() OVER (ORDER BY total_gross_spend DESC)`.
   - Computes repeat booking rates segmented by acquisition channel and overall executive KPI (~35.01%).

3. **Data Cleaning, Orphan Filtering & Analytics Flat View**:
   - `INNER JOIN` filters out invalid/orphaned booking records (99,960 clean records).
   - Standardizes `NULL` payment methods and discounts with `COALESCE`.
   - Generates derived fields: `net_booking_value`, `discount_percentage`, `days_since_signup`, `customer_booking_sequence`, and `is_repeat_booking`.

---

## Power BI DAX Measures & Funnel Modeling

Production-ready DAX expressions cataloged in [`powerbi_dax_measures.dax`](powerbi_dax_measures.dax):

- **Customer Lifetime Value (CLV)**: Dynamic cohort measure tracking cumulative net revenue per user over calendar time and relative months ($M_0, M_1, M_2, \dots$).
- **Cancellation Rate**: `[Total Cancelled Bookings] / [Total Bookings]` with full Time Intelligence support (`YTD`, `MoM % Change`, `SPLY`, and percentage-point deltas).
- **MoM Retention Rate**: Rigorous set-theoretic DAX measure using `CALCULATETABLE`, `INTERSECT`, and `VALUES(customer_id)` computing the exact overlap of active users between month $T$ and month $T-1$.
- **Booking Conversion Funnel**: Multi-stage funnel modeling:
  $$\text{Search} \xrightarrow{42\%} \text{Selection} \xrightarrow{45\%} \text{Payment Initiated} \xrightarrow{65\%} \text{Completed Transaction (12.3\% Overall)}$$
  Includes stage counts, stage-to-stage transition rates, top-of-funnel conversion %, and drop-off volumes.

---

## Project Structure

```
├── data/
│   ├── bookings.csv                # 100,000 synthetic transaction records
│   ├── customers.csv               # 35,000 customer records
│   └── marketing_campaigns.csv     # 10 promotional campaigns across channels
├── ecommerce_analytics_queries.sql # Production PostgreSQL & MySQL transformation scripts
├── powerbi_dax_measures.dax        # Enterprise Power BI DAX calculations
├── generate_dataset.py             # Statistical data generation pipeline
├── .gitignore                      # Git ignore configuration
└── README.md                       # Comprehensive documentation
```

---

## Quickstart

### 1. Generate Synthetic Data
```bash
python generate_dataset.py
```

### 2. Execute SQL Queries
Import the generated CSV files into PostgreSQL, MySQL, or SQLite, then run:
```bash
psql -U your_user -d your_db -f ecommerce_analytics_queries.sql
```

### 3. Open in Power BI
1. Connect Power BI Desktop to `data/` CSV files or PostgreSQL/MySQL database.
2. Build 1-to-many single-direction relationships between `Dim_Customer`, `Dim_Date`, `Dim_Campaign`, and `Fact_Bookings`.
3. Copy measures from `powerbi_dax_measures.dax` into your model.

---

## License

This project is licensed under the MIT License - see the LICENSE file for details.
