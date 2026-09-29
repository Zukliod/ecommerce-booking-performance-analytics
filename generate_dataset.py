import numpy as np
import pandas as pd
from faker import Faker
import datetime
import random
import sqlite3
import os

def generate_and_export_data():
    np.random.seed(42)
    random.seed(42)
    Faker.seed(42)
    
    start_date = datetime.date(2023, 1, 1)
    end_date = datetime.date(2024, 12, 31)
    total_days = (end_date - start_date).days + 1
    num_bookings = 100000
    num_customers = 35000

    print("--- 1. Generating Marketing Campaigns ---")
    campaigns_data = [
        {"campaign_id": "CMP_001", "campaign_name": "Summer Vacation Blitz", "discount_code": "SUMMER20", "channel": "Paid Search", "discount_pct": 0.20, "max_discount": 60.0},
        {"campaign_id": "CMP_002", "campaign_name": "Year-End Holiday Escapes", "discount_code": "HOLIDAY25", "channel": "Social", "discount_pct": 0.25, "max_discount": 80.0},
        {"campaign_id": "CMP_003", "campaign_name": "New User Welcome Gift", "discount_code": "WELCOME15", "channel": "Paid Search", "discount_pct": 0.15, "max_discount": 40.0},
        {"campaign_id": "CMP_004", "campaign_name": "Spring Break Getaway", "discount_code": "SPRING10", "channel": "Social", "discount_pct": 0.10, "max_discount": 30.0},
        {"campaign_id": "CMP_005", "campaign_name": "Influencer Wanderlust Promo", "discount_code": "WANDERLUST", "channel": "Social", "discount_pct": 0.15, "max_discount": 50.0},
        {"campaign_id": "CMP_006", "campaign_name": "Refer-A-Friend Program", "discount_code": "REF25OFF", "channel": "Referral", "discount_pct": 0.20, "max_discount": 50.0},
        {"campaign_id": "CMP_007", "campaign_name": "Corporate Partner Advantage", "discount_code": "CORPPERK", "channel": "Referral", "discount_pct": 0.12, "max_discount": 70.0},
        {"campaign_id": "CMP_008", "campaign_name": "Organic SEO Early Bird", "discount_code": "EARLYBIRD", "channel": "Organic", "discount_pct": 0.08, "max_discount": 25.0},
        {"campaign_id": "CMP_009", "campaign_name": "Autumn Weekend Escapes", "discount_code": "FALL10", "channel": "Organic", "discount_pct": 0.10, "max_discount": 35.0},
        {"campaign_id": "CMP_010", "campaign_name": "Google Flight Search SEM", "discount_code": "FLYSEM", "channel": "Paid Search", "discount_pct": 0.10, "max_discount": 45.0},
    ]
    df_campaigns_full = pd.DataFrame(campaigns_data)
    df_campaigns = df_campaigns_full[["campaign_id", "campaign_name", "discount_code", "channel"]].copy()

    print("--- 2. Generating Customers & Booking Allocations ---")
    customer_ids = [f"CUST_{i:06d}" for i in range(1, num_customers + 1)]
    channels = ["Organic", "Paid Search", "Social", "Referral"]
    channel_probs = [0.35, 0.30, 0.22, 0.13]
    regions = ["North America", "Europe", "Asia-Pacific", "Latin America", "Middle East"]
    region_probs = [0.40, 0.28, 0.20, 0.07, 0.05]

    assigned_channels = np.random.choice(channels, size=num_customers, p=channel_probs)
    assigned_regions = np.random.choice(regions, size=num_customers, p=region_probs)

    # Allocation of bookings per customer:
    n_single = int(num_customers * 0.65)
    n_casual = int(num_customers * 0.22)
    n_frequent = int(num_customers * 0.10)
    n_vip = num_customers - (n_single + n_casual + n_frequent)

    counts_single = np.ones(n_single, dtype=int)
    counts_casual = np.random.choice([2, 3], size=n_casual, p=[0.70, 0.30])
    counts_frequent = np.random.randint(4, 8, size=n_frequent)
    counts_vip = np.random.randint(8, 26, size=n_vip)

    counts = np.concatenate([counts_single, counts_casual, counts_frequent, counts_vip])
    np.random.shuffle(counts)

    diff = num_bookings - counts.sum()
    if diff > 0:
        add_idx = np.random.choice(np.where(counts > 1)[0], size=diff, replace=True)
        for idx in add_idx:
            counts[idx] += 1
    elif diff < 0:
        excess = -diff
        sub_idx = np.random.choice(np.where(counts > 2)[0], size=excess, replace=True)
        for idx in sub_idx:
            if counts[idx] > 2:
                counts[idx] -= 1

    rem = num_bookings - counts.sum()
    if rem != 0:
        counts[np.where(counts > 3)[0][0]] += rem

    print("--- 3. Generating Dates with Seasonality & Lifecycle ---")
    seasonality = {
        1: 0.75, 2: 0.80, 3: 1.05, 4: 1.15,
        5: 1.10, 6: 1.35, 7: 1.45, 8: 1.30,
        9: 0.90, 10: 0.95, 11: 1.20, 12: 1.40
    }
    all_dates = np.array([start_date + datetime.timedelta(days=i) for i in range(total_days)])
    day_weights = np.array([seasonality[d.month] * (1.0 + 0.12 * (d.year - start_date.year)) for d in all_dates])
    day_probs = day_weights / day_weights.sum()

    sampled_day_indices = np.random.choice(total_days, size=num_bookings, p=day_probs)

    booking_dates_list = []
    signup_dates_list = []
    
    cur_pos = 0
    for i in range(num_customers):
        cnt = counts[i]
        cust_days = sampled_day_indices[cur_pos : cur_pos + cnt]
        cust_days.sort()
        cur_pos += cnt

        first_bkg_day = cust_days[0]
        if np.random.rand() < 0.75 or first_bkg_day == 0:
            signup_day = first_bkg_day
        else:
            signup_day = max(0, first_bkg_day - np.random.randint(1, min(25, first_bkg_day + 1)))
        
        signup_dates_list.append(all_dates[signup_day])
        for d in cust_days:
            booking_dates_list.append(all_dates[d])

    df_customers = pd.DataFrame({
        "customer_id": customer_ids,
        "signup_date": [d.strftime("%Y-%m-%d") for d in signup_dates_list],
        "region": assigned_regions,
        "channel": assigned_channels
    })

    print("--- 4. Generating Bookings Attributes ---")
    cust_id_repeats = np.repeat(customer_ids, counts)
    cust_channel_repeats = np.repeat(assigned_channels, counts)

    service_types_choices = ["Flight", "Hotel", "Bus"]
    service_probs = [0.45, 0.35, 0.20]
    assigned_services = np.random.choice(service_types_choices, size=num_bookings, p=service_probs)

    gbv = np.zeros(num_bookings, dtype=float)
    flight_mask = (assigned_services == "Flight")
    hotel_mask = (assigned_services == "Hotel")
    bus_mask = (assigned_services == "Bus")

    gbv[flight_mask] = np.random.lognormal(mean=5.85, sigma=0.55, size=flight_mask.sum())
    gbv[hotel_mask] = np.random.lognormal(mean=5.45, sigma=0.65, size=hotel_mask.sum())
    gbv[bus_mask] = np.random.gamma(shape=5.0, scale=8.5, size=bus_mask.sum()) + 12.0
    gbv = np.round(np.clip(gbv, 15.0, 3500.0), 2)

    status_choices = ["Completed", "Cancelled", "Refunded"]
    booking_statuses = np.empty(num_bookings, dtype=object)
    booking_statuses[flight_mask] = np.random.choice(status_choices, size=flight_mask.sum(), p=[0.82, 0.13, 0.05])
    booking_statuses[hotel_mask] = np.random.choice(status_choices, size=hotel_mask.sum(), p=[0.71, 0.22, 0.07])
    booking_statuses[bus_mask] = np.random.choice(status_choices, size=bus_mask.sum(), p=[0.91, 0.07, 0.02])

    payment_methods_choices = ["Credit Card", "Debit Card", "Digital Wallet", "UPI/NetBanking", "BNPL"]
    payment_probs = [0.46, 0.24, 0.16, 0.10, 0.04]
    payment_methods = np.random.choice(payment_methods_choices, size=num_bookings, p=payment_probs)

    has_discount = np.random.rand(num_bookings) < 0.40
    campaign_ids = np.empty(num_bookings, dtype=object)
    campaign_ids[:] = None
    discounts_applied = np.zeros(num_bookings, dtype=float)

    camp_by_channel = {
        ch: df_campaigns_full[df_campaigns_full["channel"] == ch] for ch in channels
    }

    for ch in channels:
        ch_mask = (cust_channel_repeats == ch) & has_discount
        ch_count = ch_mask.sum()
        if ch_count > 0:
            camps = camp_by_channel[ch]
            sampled_camps = camps.sample(n=ch_count, replace=True, random_state=42)
            campaign_ids[ch_mask] = sampled_camps["campaign_id"].values
            pcts = sampled_camps["discount_pct"].values
            max_discs = sampled_camps["max_discount"].values
            calc_discs = np.minimum(gbv[ch_mask] * pcts, max_discs)
            discounts_applied[ch_mask] = np.round(calc_discs, 2)

    booking_ids = [f"BKG_{i:07d}" for i in range(1, num_bookings + 1)]
    
    df_bookings = pd.DataFrame({
        "booking_id": booking_ids,
        "customer_id": cust_id_repeats,
        "booking_date": [d.strftime("%Y-%m-%d") for d in booking_dates_list],
        "service_type": assigned_services,
        "gross_booking_value": gbv,
        "discount_applied": discounts_applied,
        "payment_method": payment_methods,
        "booking_status": booking_statuses,
        "campaign_id": campaign_ids
    })

    # Realistic anomaly injection (for SQL cleaning validation):
    # 40 orphaned bookings
    orphan_indices = np.random.choice(num_bookings, size=40, replace=False)
    df_bookings.loc[orphan_indices, "customer_id"] = "CUST_999999"

    # 60 null payment methods
    null_pm_indices = np.random.choice(num_bookings, size=60, replace=False)
    df_bookings.loc[null_pm_indices, "payment_method"] = None

    # 80 null discount applied
    null_disc_indices = np.random.choice(np.where(~has_discount)[0], size=80, replace=False)
    df_bookings.loc[null_disc_indices, "discount_applied"] = None

    print(f"Generated: Customers={len(df_customers)}, Bookings={len(df_bookings)}, Campaigns={len(df_campaigns)}")

    # Export to CSV
    csv_dir = "data"
    os.makedirs(csv_dir, exist_ok=True)
    df_customers.to_csv(os.path.join(csv_dir, "customers.csv"), index=False)
    df_bookings.to_csv(os.path.join(csv_dir, "bookings.csv"), index=False)
    df_campaigns.to_csv(os.path.join(csv_dir, "marketing_campaigns.csv"), index=False)
    print("Exported CSVs successfully to data/ directory.")

    # Save to SQLite for SQL query verification
    db_path = "ecommerce_booking.db"
    conn = sqlite3.connect(db_path)
    df_customers.to_sql("customers", conn, if_exists="replace", index=False)
    df_bookings.to_sql("bookings", conn, if_exists="replace", index=False)
    df_campaigns.to_sql("marketing_campaigns", conn, if_exists="replace", index=False)
    
    # Create indexes for high performance
    cursor = conn.cursor()
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_cust_id ON customers(customer_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_bkg_cust ON bookings(customer_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_bkg_date ON bookings(booking_date);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_bkg_status ON bookings(booking_status);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_bkg_service ON bookings(service_type);")
    conn.commit()
    conn.close()
    print("Database ecommerce_booking.db created and indexed successfully.")

if __name__ == "__main__":
    generate_and_export_data()
