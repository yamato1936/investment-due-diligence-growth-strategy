-- ============================================================
-- Olist Diagnostic Analysis: Growth
-- ============================================================

-- ============================================================
-- 0. Sources
-- ============================================================

CREATE OR REPLACE TEMP VIEW order_base AS
SELECT *
FROM read_parquet('data/processed/order_base.parquet');

CREATE OR REPLACE TEMP VIEW item_base AS
SELECT *
FROM read_parquet('data/processed/item_base.parquet');

CREATE OR REPLACE TEMP VIEW orders_all AS
SELECT *
FROM read_csv_auto('data/raw/olist_orders_dataset.csv');

CREATE OR REPLACE TEMP VIEW customers_all AS
SELECT *
FROM read_csv_auto('data/raw/olist_customers_dataset.csv');


-- ============================================================
-- 1. Monthly Growth
-- ============================================================

-- Objective:
--   Determine whether the business is growing over the analysis window
--   and whether growth is driven primarily by order volume, customer
--   activity, or merchandise value per order.
--
-- Metric definitions:
--   Placed Orders        = distinct orders in order_base
--   Active Customers     = distinct customer_unique_id in order_base
--   Merchandise GMV      = SUM(item_base.merchandise_value)
--   GMV Orders           = distinct orders represented in item_base
--   AOV                  = Merchandise GMV / GMV Orders
--
-- Note:
--   AOV uses GMV Orders rather than all placed orders so that its
--   numerator and denominator refer to the same order population.


-- ============================================================
-- 1.1 Monthly KPI Levels
-- ============================================================

CREATE OR REPLACE TEMP VIEW monthly_order_metrics AS
SELECT
    purchase_month,
    COUNT(DISTINCT order_id) AS placed_orders,
    COUNT(DISTINCT customer_unique_id) AS active_customers
FROM order_base
GROUP BY purchase_month;


CREATE OR REPLACE TEMP VIEW monthly_item_metrics AS
SELECT
    purchase_month,
    ROUND(SUM(merchandise_value), 2) AS merchandise_gmv,
    COUNT(DISTINCT order_id) AS gmv_orders
FROM item_base
GROUP BY purchase_month;


CREATE OR REPLACE TEMP VIEW monthly_growth AS
SELECT
    o.purchase_month,

    o.placed_orders,
    o.active_customers,

    i.gmv_orders,
    i.merchandise_gmv,

    ROUND(
        i.merchandise_gmv
        / NULLIF(i.gmv_orders, 0),
        2
    ) AS aov,

    ROUND(
        100.0 * i.gmv_orders
        / NULLIF(o.placed_orders, 0),
        2
    ) AS gmv_order_coverage_pct

FROM monthly_order_metrics o
LEFT JOIN monthly_item_metrics i USING (purchase_month);


SELECT
    STRFTIME(purchase_month, '%Y-%m') AS month,
    placed_orders,
    active_customers,
    gmv_orders,
    merchandise_gmv,
    aov,
    gmv_order_coverage_pct
FROM monthly_growth
ORDER BY purchase_month;


-- ============================================================
-- 1.2 Core Growth Metrics
-- ============================================================

SELECT
    STRFTIME(purchase_month, '%Y-%m') AS month,
    placed_orders,
    active_customers,
    merchandise_gmv,
    aov
FROM monthly_growth
ORDER BY purchase_month;

-- ============================================================
-- 2. Customer Growth Composition
-- ============================================================

-- Objective:
--   Determine whether monthly customer activity is driven primarily
--   by first-observed customers or returning customers.
--
-- Definition:
--   New customer =
--     customer_unique_id whose first observed purchase month in the
--     full available dataset equals the current purchase month.
--
--   Returning customer =
--     customer_unique_id with an observed purchase before the
--     current purchase month.
--
-- Limitation:
--   "New" means first observed purchase in this dataset, not necessarily
--   the customer's true lifetime first purchase. The dataset is
--   left-censored before the observation period.


-- ============================================================
-- 2.1 First Observed Purchase
-- ============================================================

CREATE OR REPLACE TEMP VIEW customer_first_purchase AS
SELECT
    c.customer_unique_id,
    MIN(o.order_purchase_timestamp) AS first_observed_purchase_at,
    DATE_TRUNC(
        'month',
        MIN(o.order_purchase_timestamp)
    ) AS first_observed_purchase_month
FROM orders_all o
JOIN customers_all c USING (customer_id)
GROUP BY c.customer_unique_id;


-- ============================================================
-- 2.2 Customer-Month Grain
-- ============================================================

-- Grain:
--   1 row = 1 customer_unique_id x purchase_month

CREATE OR REPLACE TEMP VIEW customer_month AS
SELECT DISTINCT
    ob.purchase_month,
    ob.customer_unique_id,
    fp.first_observed_purchase_month
FROM order_base ob
JOIN customer_first_purchase fp USING (customer_unique_id);


-- ============================================================
-- 2.3 Monthly New vs Returning Customers
-- ============================================================

CREATE OR REPLACE TEMP VIEW monthly_customer_mix AS
SELECT
    purchase_month,

    COUNT(*) AS active_customers,

    COUNT(*) FILTER (
        WHERE first_observed_purchase_month = purchase_month
    ) AS new_customers,

    COUNT(*) FILTER (
        WHERE first_observed_purchase_month < purchase_month
    ) AS returning_customers

FROM customer_month
GROUP BY purchase_month;


SELECT
    STRFTIME(m.purchase_month, '%Y-%m') AS month,

    m.active_customers,
    m.new_customers,
    m.returning_customers,

    ROUND(
        100.0 * m.new_customers
        / NULLIF(m.active_customers, 0),
        2
    ) AS new_customer_share_pct,

    ROUND(
        100.0 * m.returning_customers
        / NULLIF(m.active_customers, 0),
        2
    ) AS returning_customer_share_pct,

    ROUND(
        1.0 * g.placed_orders
        / NULLIF(m.active_customers, 0),
        3
    ) AS orders_per_active_customer

FROM monthly_customer_mix m
JOIN monthly_growth g USING (purchase_month)
ORDER BY m.purchase_month;


-- ============================================================
-- 3. 90-Day Customer Repeat
-- ============================================================

-- Objective:
--   Measure whether first-observed customers generate repeat
--   purchasing within 90 days.
--
-- Denominator:
--   Customers whose first observed purchase occurs early enough
--   to allow a full 90-day follow-up period.
--
-- Repeat:
--   At least one subsequent order within 90 days after the
--   first observed purchase.


-- ============================================================
-- 3.1 Customer Purchase Sequence
-- ============================================================

CREATE OR REPLACE TEMP VIEW customer_orders_all AS
SELECT
    c.customer_unique_id,
    o.order_id,
    o.order_purchase_timestamp,

    ROW_NUMBER() OVER (
        PARTITION BY c.customer_unique_id
        ORDER BY
            o.order_purchase_timestamp,
            o.order_id
    ) AS purchase_number

FROM orders_all o
JOIN customers_all c USING (customer_id);


-- ============================================================
-- 3.2 First and Second Purchase
-- ============================================================

CREATE OR REPLACE TEMP VIEW customer_purchase_summary AS
SELECT
    customer_unique_id,

    MIN(order_purchase_timestamp) FILTER (
        WHERE purchase_number = 1
    ) AS first_purchase_at,

    MIN(order_purchase_timestamp) FILTER (
        WHERE purchase_number = 2
    ) AS second_purchase_at

FROM customer_orders_all
GROUP BY customer_unique_id;


-- ============================================================
-- 3.3 90-Day Repeat by Acquisition Cohort
-- ============================================================

SELECT
    STRFTIME(
        DATE_TRUNC('month', first_purchase_at),
        '%Y-%m'
    ) AS acquisition_month,

    COUNT(*) AS eligible_customers,

    COUNT(*) FILTER (
        WHERE second_purchase_at IS NOT NULL
          AND second_purchase_at <= first_purchase_at + INTERVAL '90 days'
    ) AS repeated_within_90d,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE second_purchase_at IS NOT NULL
              AND second_purchase_at <= first_purchase_at + INTERVAL '90 days'
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS repeat_90d_pct

FROM customer_purchase_summary

WHERE first_purchase_at >= TIMESTAMP '2017-02-01'
  AND first_purchase_at <  TIMESTAMP '2018-06-01'

GROUP BY 1
ORDER BY 1;