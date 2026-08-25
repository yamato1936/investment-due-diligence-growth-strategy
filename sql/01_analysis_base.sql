-- ============================================================
-- Olist Analytical Base
-- ============================================================
-- Purpose:
--   Build canonical analytical bases for downstream diagnostic
--   analysis and investment decision-making.
--
-- Design:
--   - order_base: 1 row = 1 order
--   - item_base:  1 row = 1 order item (added in next step)
--   - Payments are aggregated to order grain before joining
--   - Reviews use the canonical latest review per order
--   - Metric-specific anomalies are retained and handled through
--     eligibility flags rather than global row deletion
--
-- Analysis window:
--   2017-02-01 <= order_purchase_timestamp < 2018-09-01
-- ============================================================


-- ============================================================
-- 0. Sources
-- ============================================================

CREATE OR REPLACE TEMP VIEW orders AS
SELECT *
FROM read_csv_auto('data/raw/olist_orders_dataset.csv');

CREATE OR REPLACE TEMP VIEW customers AS
SELECT *
FROM read_csv_auto('data/raw/olist_customers_dataset.csv');

CREATE OR REPLACE TEMP VIEW order_payments AS
SELECT *
FROM read_csv_auto('data/raw/olist_order_payments_dataset.csv');

CREATE OR REPLACE TEMP VIEW order_reviews AS
SELECT *
FROM read_csv_auto('data/raw/olist_order_reviews_dataset.csv');

CREATE OR REPLACE TEMP VIEW order_items AS
SELECT *
FROM read_csv_auto('data/raw/olist_order_items_dataset.csv');

CREATE OR REPLACE TEMP VIEW products AS
SELECT *
FROM read_csv_auto('data/raw/olist_products_dataset.csv');

CREATE OR REPLACE TEMP VIEW category_translation AS
SELECT *
FROM read_csv_auto('data/raw/product_category_name_translation.csv');

CREATE OR REPLACE TEMP VIEW sellers AS
SELECT *
FROM read_csv_auto('data/raw/olist_sellers_dataset.csv');


-- ============================================================
-- 1. Analysis Orders
-- ============================================================

-- Canonical order population for all downstream analysis.
-- Grain: 1 row = 1 order
-- Unique key: order_id

CREATE OR REPLACE TEMP VIEW analysis_orders AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    DATE_TRUNC('month', order_purchase_timestamp) AS purchase_month
FROM orders
WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
  AND order_purchase_timestamp <  TIMESTAMP '2018-09-01';

-- 1.1 Grain / analysis-window validation

SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids,
    MIN(order_purchase_timestamp) AS min_purchase_timestamp,
    MAX(order_purchase_timestamp) AS max_purchase_timestamp
FROM analysis_orders;


-- ============================================================
-- 2. Payments: Order-Level Aggregation
-- ============================================================

-- Raw payments are 1:N relative to orders.
-- Aggregate to order grain before joining to avoid row multiplication.
--
-- Customer payment value is a payment measure and must not be treated
-- as merchandise GMV or company revenue.

CREATE OR REPLACE TEMP VIEW payments_order_agg AS
SELECT
    p.order_id,
    ROUND(SUM(p.payment_value), 2) AS customer_payment_value,
    COUNT(*) AS payment_sequence_count,
    MAX(p.payment_installments) AS max_payment_installments,
    COUNT(DISTINCT p.payment_type) AS payment_type_count
FROM order_payments p
JOIN analysis_orders ao USING (order_id)
GROUP BY p.order_id;

-- 2.1 Grain / coverage validation

SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids,
    COUNT(*) FILTER (
        WHERE customer_payment_value IS NULL
    ) AS null_payment_values
FROM payments_order_agg;


-- ============================================================
-- 3. Reviews: Canonical Latest Review
-- ============================================================

-- Raw reviews may contain multiple records per order.
-- For order-level review metrics, retain the latest review using the
-- deterministic rule established during the data audit:
--
--   review_answer_timestamp DESC
--   review_creation_date DESC
--   review_id DESC
--
-- Do not average multiple review scores for the same order.

CREATE OR REPLACE TEMP VIEW latest_review AS
WITH ranked_reviews AS (
    SELECT
        r.order_id,
        r.review_id,
        r.review_score,
        r.review_creation_date,
        r.review_answer_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY
                r.review_answer_timestamp DESC,
                r.review_creation_date DESC,
                r.review_id DESC
        ) AS rn
    FROM order_reviews r
    JOIN analysis_orders ao USING (order_id)
)

SELECT
    order_id,
    review_id,
    review_score,
    review_creation_date,
    review_answer_timestamp
FROM ranked_reviews
WHERE rn = 1;

-- 3.1 Grain / coverage validation

SELECT
    COUNT(*) AS review_rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids,
    COUNT(*) FILTER (
        WHERE review_score IS NULL
    ) AS null_review_scores
FROM latest_review;


-- ============================================================
-- 4. Order Base
-- ============================================================

-- Canonical order-level analytical base.
--
-- Grain:
--   1 row = 1 order
--
-- Unique key:
--   order_id
--
-- Primary use cases:
--   - monthly order growth
--   - active customers
--   - customer geography
--   - repeat behavior
--   - payment behavior
--   - delivery performance
--   - review metrics
--
-- Reviews are LEFT JOINed because review availability defines
-- eligibility for review KPIs and must not remove otherwise valid orders.

CREATE OR REPLACE TEMP VIEW order_base AS
SELECT
    -- Identifiers
    ao.order_id,
    ao.customer_id,
    c.customer_unique_id,

    -- Time
    ao.order_purchase_timestamp,
    ao.purchase_month,

    -- Customer geography
    c.customer_city,
    c.customer_state,

    -- Lifecycle
    ao.order_status,

    -- Payment
    p.customer_payment_value,
    p.payment_sequence_count,
    p.max_payment_installments,
    p.payment_type_count,

    -- Review
    r.review_id,
    r.review_score,
    r.review_creation_date,
    r.review_answer_timestamp,

    -- Fulfillment timestamps
    ao.order_approved_at,
    ao.order_delivered_carrier_date,
    ao.order_delivered_customer_date,
    ao.order_estimated_delivery_date,

    -- Fulfillment metrics
    DATE_DIFF(
        'day',
        ao.order_purchase_timestamp,
        ao.order_delivered_customer_date
    ) AS delivery_days,

    CASE
        WHEN ao.order_delivered_customer_date IS NOT NULL
         AND ao.order_estimated_delivery_date IS NOT NULL
        THEN ao.order_delivered_customer_date
             > ao.order_estimated_delivery_date
        ELSE NULL
    END AS late_delivery_flag,

    -- Metric-specific eligibility
    CASE
        WHEN ao.order_delivered_customer_date IS NOT NULL
         AND ao.order_delivered_carrier_date IS NOT NULL
         AND ao.order_delivered_customer_date
                >= ao.order_delivered_carrier_date
         AND ao.order_delivered_customer_date
                >= ao.order_purchase_timestamp
        THEN TRUE
        ELSE FALSE
    END AS delivery_time_eligible,

    CASE
        WHEN ao.order_delivered_customer_date IS NOT NULL
         AND ao.order_estimated_delivery_date IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS late_delivery_eligible,

    CASE
        WHEN r.review_score IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS review_eligible

FROM analysis_orders ao

JOIN customers c USING (customer_id)

LEFT JOIN payments_order_agg p USING (order_id)

LEFT JOIN latest_review r USING (order_id);


-- ============================================================
-- 5. Order Base Validation
-- ============================================================

-- 5.1 Grain / join integrity / critical coverage

SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids,

    COUNT(*) FILTER (
        WHERE customer_unique_id IS NULL
    ) AS missing_customer,

    COUNT(*) FILTER (
        WHERE customer_payment_value IS NULL
    ) AS missing_payment,

    COUNT(*) FILTER (
        WHERE review_score IS NULL
    ) AS missing_review

FROM order_base;


-- ============================================================
-- 6. Item Base
-- ============================================================

-- Canonical item-level analytical base.
--
-- Grain:
--   1 row = 1 order item
--
-- Unique key:
--   (order_id, order_item_id)
--
-- Primary use cases:
--   - merchandise GMV
--   - product / category analysis
--   - seller analysis
--   - freight analysis
--   - category x geography x time analysis
--
-- Order-level payment, review, and delivery metrics are intentionally
-- not joined into this base because they would be duplicated across
-- multiple items within the same order.

CREATE OR REPLACE TEMP VIEW item_base AS
SELECT
    -- Identifiers
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,

    -- Time
    ao.order_purchase_timestamp,
    ao.purchase_month,

    -- Order
    ao.order_status,

    -- Customer geography
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,

    -- Product / category
    p.product_category_name,

    CASE
        WHEN p.product_category_name IS NULL
            THEN 'Unknown'
        WHEN t.product_category_name_english IS NULL
            THEN 'Untranslated'
        ELSE t.product_category_name_english
    END AS product_category_name_english,

    -- Seller geography
    s.seller_city,
    s.seller_state,

    -- Item-level monetary measures
    i.price AS merchandise_value,
    i.freight_value AS freight_charged

FROM order_items i

JOIN analysis_orders ao USING (order_id)

JOIN customers c USING (customer_id)

JOIN products p USING (product_id)

LEFT JOIN category_translation t USING (product_category_name)

JOIN sellers s USING (seller_id);


-- ============================================================
-- 7. Item Base Validation
-- ============================================================

-- 7.1 Grain / join integrity / category coverage

WITH duplicate_pairs AS (
    SELECT
        order_id,
        order_item_id
    FROM item_base
    GROUP BY
        order_id,
        order_item_id
    HAVING COUNT(*) > 1
)

SELECT
    COUNT(DISTINCT order_id) AS distinct_order_ids,

    (SELECT COUNT(*)
     FROM duplicate_pairs) AS duplicate_order_item_pairs,

    COUNT(*) FILTER (
        WHERE product_id IS NULL
    ) AS missing_product,

    COUNT(*) FILTER (
        WHERE seller_id IS NULL
    ) AS missing_seller

FROM item_base;


-- ============================================================
-- 8. Materialize Analytical Bases
-- ============================================================

COPY (
    SELECT *
    FROM order_base
)
TO 'data/processed/order_base.parquet'
(FORMAT PARQUET);

COPY (
    SELECT *
    FROM item_base
)
TO 'data/processed/item_base.parquet'
(FORMAT PARQUET);


