-- ============================================================
-- Olist Data Audit
-- ============================================================
-- Purpose:
--   Validate analytical grain, keys, joins, value integrity,
--   temporal coverage, and metric eligibility before analysis.
--
-- Final audit decisions:
--   - Analysis window: 2017-02-01 <= purchase_timestamp < 2018-09-01
--   - Do not globally drop anomalous rows. Use metric-specific eligibility
--   - Merchandise GMV = SUM(order_items.price)
--   - Raw geolocation is not safe to join on ZIP prefix without aggregation
--   - Order-level review metrics should use the latest review, not AVG(score)
-- ============================================================

-- ============================================================
-- 0. Sources
-- ============================================================
CREATE OR REPLACE TEMP VIEW orders AS
SELECT * FROM read_csv_auto('data/raw/olist_orders_dataset.csv');

CREATE OR REPLACE TEMP VIEW customers AS
SELECT * FROM read_csv_auto('data/raw/olist_customers_dataset.csv');

CREATE OR REPLACE TEMP VIEW order_items AS
SELECT * FROM read_csv_auto('data/raw/olist_order_items_dataset.csv');

CREATE OR REPLACE TEMP VIEW products AS
SELECT * FROM read_csv_auto('data/raw/olist_products_dataset.csv');

CREATE OR REPLACE TEMP VIEW category_translation AS
SELECT * FROM read_csv_auto('data/raw/product_category_name_translation.csv');

CREATE OR REPLACE TEMP VIEW sellers AS
SELECT * FROM read_csv_auto('data/raw/olist_sellers_dataset.csv');

CREATE OR REPLACE TEMP VIEW order_payments AS
SELECT * FROM read_csv_auto('data/raw/olist_order_payments_dataset.csv');

CREATE OR REPLACE TEMP VIEW geolocation AS
SELECT * FROM read_csv_auto('data/raw/olist_geolocation_dataset.csv');

CREATE OR REPLACE TEMP VIEW order_reviews AS
SELECT * FROM read_csv_auto('data/raw/olist_order_reviews_dataset.csv');


-- ============================================================
-- 1. Orders
-- ============================================================

-- 1.1 Grain / key integrity
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_ids
FROM orders;

-- 1.2 Lifecycle distribution
SELECT
    order_status,
    COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS order_pct
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- 1.3 Timestamp missingness by lifecycle state
SELECT
    order_status,
    COUNT(*) AS orders,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL) AS approved_nulls,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL) AS carrier_nulls,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS delivered_nulls
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- 1.4 Realized-event consistency and delivery lateness
-- Expected realized ordering: purchase <= approval <= carrier <= delivered.
-- Estimated delivery is a target, not a realized event timestamp.
SELECT
    COUNT(*) FILTER (
        WHERE order_approved_at < order_purchase_timestamp
    ) AS approved_before_purchase,
    COUNT(*) FILTER (
        WHERE order_delivered_carrier_date < order_approved_at
    ) AS carrier_before_approval,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date < order_delivered_carrier_date
    ) AS delivered_before_carrier,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date < order_purchase_timestamp
    ) AS delivered_before_purchase,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date > order_estimated_delivery_date
    ) AS late_deliveries
FROM orders;

-- 1.5 Temporal coverage
SELECT
    COUNT(*) AS orders,
    MIN(order_purchase_timestamp) AS min_purchase_at,
    MAX(order_purchase_timestamp) AS max_purchase_at
FROM orders;

WITH bounds AS (
    SELECT
        DATE_TRUNC('month', MIN(order_purchase_timestamp)) AS min_month,
        DATE_TRUNC('month', MAX(order_purchase_timestamp)) AS max_month
    FROM orders
),
calendar AS (
    SELECT month
    FROM bounds,
    UNNEST(GENERATE_SERIES(min_month, max_month, INTERVAL '1 month')) AS t(month)
),
monthly_orders AS (
    SELECT
        DATE_TRUNC('month', order_purchase_timestamp) AS month,
        COUNT(*) AS orders,
        MIN(order_purchase_timestamp) AS first_purchase_at,
        MAX(order_purchase_timestamp) AS last_purchase_at
    FROM orders
    GROUP BY 1
)
SELECT
    STRFTIME(c.month, '%Y-%m') AS month,
    COALESCE(m.orders, 0) AS orders,
    m.first_purchase_at,
    m.last_purchase_at
FROM calendar c
LEFT JOIN monthly_orders m USING (month)
ORDER BY c.month;

-- Final analysis window after temporal + cross-table validation.
CREATE OR REPLACE TEMP VIEW analysis_orders AS
SELECT *
FROM orders
WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
  AND order_purchase_timestamp <  TIMESTAMP '2018-09-01';

SELECT
    COUNT(*) AS analysis_orders,
    MIN(order_purchase_timestamp) AS min_purchase_at,
    MAX(order_purchase_timestamp) AS max_purchase_at
FROM analysis_orders;


-- ============================================================
-- 2. Customers
-- ============================================================

-- 2.1 Grain, identity relationship, and geography completeness
WITH customer_identity AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT customer_id) AS customer_ids
    FROM customers
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    COUNT(DISTINCT customer_unique_id) AS distinct_customer_unique_ids,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_ids,
    COUNT(*) FILTER (WHERE customer_unique_id IS NULL) AS null_customer_unique_ids,
    (SELECT COUNT(*) FROM customer_identity WHERE customer_ids > 1)
        AS unique_customers_with_multiple_customer_ids,
    (SELECT MAX(customer_ids) FROM customer_identity)
        AS max_customer_ids_per_unique_customer,
    COUNT(*) FILTER (WHERE customer_zip_code_prefix IS NULL) AS null_zip_codes,
    COUNT(*) FILTER (WHERE customer_city IS NULL) AS null_cities,
    COUNT(*) FILTER (WHERE customer_state IS NULL) AS null_states
FROM customers;

-- 2.2 Orders <-> customers must be one-to-one on customer_id
SELECT
    (SELECT COUNT(*) FROM orders) AS order_rows,
    (SELECT COUNT(DISTINCT customer_id) FROM orders) AS distinct_order_customer_ids,
    (SELECT COUNT(*) FROM orders o JOIN customers c USING (customer_id)) AS joined_rows,
    (SELECT COUNT(*)
     FROM orders o LEFT JOIN customers c USING (customer_id)
     WHERE c.customer_id IS NULL) AS unmatched_orders,
    (SELECT COUNT(*)
     FROM customers c LEFT JOIN orders o USING (customer_id)
     WHERE o.customer_id IS NULL) AS unmatched_customers;


-- ============================================================
-- 3. Order Items
-- ============================================================

-- 3.1 Grain / composite key / null keys
WITH duplicate_pairs AS (
    SELECT order_id, order_item_id
    FROM order_items
    GROUP BY order_id, order_item_id
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_ids,
    COUNT(*) FILTER (WHERE order_item_id IS NULL) AS null_order_item_ids,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS null_product_ids,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS null_seller_ids,
    (SELECT COUNT(*) FROM duplicate_pairs) AS duplicate_order_item_pairs
FROM order_items;

-- 3.2 Orders <-> items coverage and item-less orders by lifecycle state
SELECT
    o.order_status,
    COUNT(*) AS orders_without_items
FROM orders o
LEFT JOIN (SELECT DISTINCT order_id FROM order_items) i USING (order_id)
WHERE i.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;

SELECT
    (SELECT COUNT(*) FROM order_items) AS item_rows,
    (SELECT COUNT(*) FROM orders o JOIN order_items i USING (order_id)) AS joined_item_rows,
    (SELECT COUNT(*)
     FROM order_items i LEFT JOIN orders o USING (order_id)
     WHERE o.order_id IS NULL) AS item_rows_without_order;

-- 3.3 Price / freight integrity and upper-tail diagnostics
SELECT
    'price' AS metric,
    COUNT(*) FILTER (WHERE price IS NULL) AS null_values,
    COUNT(*) FILTER (WHERE price < 0) AS negative_values,
    COUNT(*) FILTER (WHERE price = 0) AS zero_values,
    MIN(price) AS min_value,
    MEDIAN(price) AS median_value,
    quantile_cont(price, 0.95) AS p95_value,
    quantile_cont(price, 0.99) AS p99_value,
    MAX(price) AS max_value
FROM order_items
UNION ALL
SELECT
    'freight_value',
    COUNT(*) FILTER (WHERE freight_value IS NULL),
    COUNT(*) FILTER (WHERE freight_value < 0),
    COUNT(*) FILTER (WHERE freight_value = 0),
    MIN(freight_value),
    MEDIAN(freight_value),
    quantile_cont(freight_value, 0.95),
    quantile_cont(freight_value, 0.99),
    MAX(freight_value)
FROM order_items;

CREATE OR REPLACE TEMP VIEW item_order_totals AS
SELECT
    order_id,
    ROUND(SUM(price), 2) AS item_gmv,
    ROUND(SUM(freight_value), 2) AS freight_total,
    ROUND(SUM(price + freight_value), 2) AS item_plus_freight
FROM order_items
GROUP BY order_id;


-- ============================================================
-- 4. Products / Category Translation
-- ============================================================

-- 4.1 Product grain and category completeness
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT product_id) AS distinct_product_ids,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS null_product_ids,
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS null_category_names
FROM products;

-- 4.2 Product join coverage and missing-category GMV exposure
SELECT
    (SELECT COUNT(*) FROM order_items) AS item_rows,
    (SELECT COUNT(*) FROM order_items i JOIN products p USING (product_id)) AS joined_item_rows,
    (SELECT COUNT(*)
     FROM order_items i LEFT JOIN products p USING (product_id)
     WHERE p.product_id IS NULL) AS item_rows_without_product,
    (SELECT COUNT(*)
     FROM products p LEFT JOIN order_items i USING (product_id)
     WHERE i.product_id IS NULL) AS products_without_items,
    (SELECT COUNT(*)
     FROM order_items i JOIN products p USING (product_id)
     WHERE p.product_category_name IS NULL) AS null_category_item_rows,
    ROUND((SELECT SUM(i.price)
           FROM order_items i JOIN products p USING (product_id)
           WHERE p.product_category_name IS NULL), 2) AS null_category_item_gmv,
    ROUND(100.0 *
        (SELECT SUM(i.price)
         FROM order_items i JOIN products p USING (product_id)
         WHERE p.product_category_name IS NULL)
        / (SELECT SUM(price) FROM order_items), 3) AS null_category_gmv_pct;

-- 4.3 Translation key / coverage
SELECT
    (SELECT COUNT(*) FROM category_translation) AS translation_rows,
    (SELECT COUNT(DISTINCT product_category_name) FROM category_translation)
        AS distinct_translation_categories,
    (SELECT COUNT(DISTINCT product_category_name)
     FROM products WHERE product_category_name IS NOT NULL)
        AS distinct_product_categories,
    (SELECT COUNT(*)
     FROM products p
     LEFT JOIN category_translation t USING (product_category_name)
     WHERE p.product_category_name IS NOT NULL
       AND t.product_category_name IS NULL) AS products_with_untranslated_category,
    (SELECT COUNT(*)
     FROM order_items i
     JOIN products p USING (product_id)
     LEFT JOIN category_translation t USING (product_category_name)
     WHERE p.product_category_name IS NOT NULL
       AND t.product_category_name IS NULL) AS item_rows_with_untranslated_category,
    ROUND((SELECT SUM(i.price)
           FROM order_items i
           JOIN products p USING (product_id)
           LEFT JOIN category_translation t USING (product_category_name)
           WHERE p.product_category_name IS NOT NULL
             AND t.product_category_name IS NULL), 2) AS untranslated_item_gmv;


-- ============================================================
-- 5. Sellers
-- ============================================================
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT seller_id) AS distinct_seller_ids,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS null_seller_ids,
    COUNT(*) FILTER (WHERE seller_zip_code_prefix IS NULL) AS null_zip_codes,
    COUNT(*) FILTER (WHERE seller_city IS NULL) AS null_cities,
    COUNT(*) FILTER (WHERE seller_state IS NULL) AS null_states,
    (SELECT COUNT(*)
     FROM order_items i LEFT JOIN sellers s USING (seller_id)
     WHERE s.seller_id IS NULL) AS item_rows_without_seller,
    (SELECT COUNT(*)
     FROM sellers s LEFT JOIN order_items i USING (seller_id)
     WHERE i.seller_id IS NULL) AS sellers_without_items
FROM sellers;


-- ============================================================
-- 6. Payments
-- ============================================================

-- 6.1 Grain / composite key / coverage
WITH duplicate_pairs AS (
    SELECT order_id, payment_sequential
    FROM order_payments
    GROUP BY order_id, payment_sequential
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_ids,
    COUNT(*) FILTER (WHERE payment_sequential IS NULL) AS null_payment_sequential,
    COUNT(*) FILTER (WHERE payment_type IS NULL) AS null_payment_type,
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS null_payment_value,
    (SELECT COUNT(*) FROM duplicate_pairs) AS duplicate_payment_pairs,
    (SELECT COUNT(*)
     FROM orders o LEFT JOIN order_payments p USING (order_id)
     WHERE p.order_id IS NULL) AS orders_without_payments,
    (SELECT COUNT(*)
     FROM order_payments p LEFT JOIN orders o USING (order_id)
     WHERE o.order_id IS NULL) AS payment_rows_without_order
FROM order_payments;

-- 6.2 Numeric integrity
SELECT
    COUNT(*) FILTER (WHERE payment_value < 0) AS negative_payment_value,
    COUNT(*) FILTER (WHERE payment_value = 0) AS zero_payment_value,
    COUNT(*) FILTER (WHERE payment_installments < 0) AS negative_installments,
    COUNT(*) FILTER (WHERE payment_installments = 0) AS zero_installments
FROM order_payments;

CREATE OR REPLACE TEMP VIEW payment_order_totals AS
SELECT
    order_id,
    CASE
        WHEN COUNT(DISTINCT payment_type) = 1 THEN MAX(payment_type)
        ELSE 'mixed'
    END AS payment_profile,
    MAX(payment_installments) AS max_installments,
    ROUND(SUM(payment_value), 2) AS payment_total
FROM order_payments
GROUP BY order_id;

CREATE OR REPLACE TEMP VIEW payment_reconciliation AS
SELECT
    i.order_id,
    o.order_status,
    p.payment_profile,
    p.max_installments,
    i.item_plus_freight,
    p.payment_total,
    ROUND(p.payment_total - i.item_plus_freight, 2) AS difference,
    ABS(p.payment_total - i.item_plus_freight)
        / NULLIF(i.item_plus_freight, 0) AS relative_difference
FROM item_order_totals i
JOIN payment_order_totals p USING (order_id)
JOIN orders o USING (order_id);

-- 6.3 Reconciliation summary
SELECT
    COUNT(*) AS reconciled_orders,
    COUNT(*) FILTER (WHERE ABS(difference) > 0.01) AS difference_orders,
    COUNT(*) FILTER (WHERE difference > 0.01) AS payment_higher_orders,
    COUNT(*) FILTER (WHERE difference < -0.01) AS payment_lower_orders,
    ROUND(SUM(ABS(difference)), 2) AS sum_absolute_difference,
    ROUND(MEDIAN(100.0 * relative_difference)
          FILTER (WHERE ABS(difference) > 0.01), 2) AS median_relative_diff_pct,
    ROUND(MAX(100.0 * relative_difference)
          FILTER (WHERE ABS(difference) > 0.01), 2) AS max_relative_diff_pct
FROM payment_reconciliation;

-- Note: reconciliation differences are rare but non-random. Treat payment_value
-- as a separate payment measure rather than a substitute for merchandise GMV.


-- ============================================================
-- 7. Geolocation
-- ============================================================
-- Raw geolocation is many rows per ZIP prefix. Use customer/seller
-- city/state for categorical geography. Aggregate ZIPs before any
-- latitude/longitude join.
WITH zip_stats AS (
    SELECT
        geolocation_zip_code_prefix,
        COUNT(*) AS rows_per_zip,
        COUNT(DISTINCT geolocation_city) AS cities,
        COUNT(DISTINCT geolocation_state) AS states
    FROM geolocation
    GROUP BY geolocation_zip_code_prefix
)
SELECT
    (SELECT COUNT(*) FROM geolocation) AS rows,
    (SELECT COUNT(*) FROM zip_stats) AS distinct_zip_codes,
    (SELECT MAX(rows_per_zip) FROM zip_stats) AS max_rows_per_zip,
    (SELECT COUNT(*) FROM zip_stats WHERE cities > 1) AS zip_codes_with_multiple_cities,
    (SELECT COUNT(*) FROM zip_stats WHERE states > 1) AS zip_codes_with_multiple_states,
    COUNT(*) FILTER (WHERE geolocation_zip_code_prefix IS NULL) AS null_zip_codes,
    COUNT(*) FILTER (WHERE geolocation_lat IS NULL) AS null_latitudes,
    COUNT(*) FILTER (WHERE geolocation_lng IS NULL) AS null_longitudes
FROM geolocation;

CREATE OR REPLACE TEMP VIEW geo_zip_keys AS
SELECT DISTINCT geolocation_zip_code_prefix
FROM geolocation;

-- Coordinate coverage in the final analysis window
SELECT
    (SELECT COUNT(*) FROM analysis_orders) AS analysis_orders,
    (SELECT COUNT(*)
     FROM analysis_orders o
     JOIN customers c USING (customer_id)
     LEFT JOIN geo_zip_keys g
       ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
     WHERE g.geolocation_zip_code_prefix IS NULL) AS orders_with_customer_geo_missing,
    ROUND((SELECT SUM(i.price)
           FROM analysis_orders o
           JOIN customers c USING (customer_id)
           JOIN order_items i USING (order_id)
           LEFT JOIN geo_zip_keys g
             ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
           WHERE g.geolocation_zip_code_prefix IS NULL), 2)
        AS gmv_with_customer_geo_missing,
    ROUND((SELECT SUM(i.price)
           FROM analysis_orders o
           JOIN order_items i USING (order_id)
           JOIN sellers s USING (seller_id)
           LEFT JOIN geo_zip_keys g
             ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix
           WHERE g.geolocation_zip_code_prefix IS NULL), 2)
        AS gmv_with_seller_geo_missing;


-- ============================================================
-- 8. Reviews
-- ============================================================

-- 8.1 Grain / multiplicity / coverage
WITH review_to_order AS (
    SELECT review_id, COUNT(DISTINCT order_id) AS orders_per_review
    FROM order_reviews
    GROUP BY review_id
),
order_to_review AS (
    SELECT order_id, COUNT(DISTINCT review_id) AS reviews_per_order
    FROM order_reviews
    GROUP BY order_id
),
pairs AS (
    SELECT review_id, order_id, COUNT(*) AS rows_per_pair
    FROM order_reviews
    GROUP BY review_id, order_id
)
SELECT
    (SELECT COUNT(*) FROM order_reviews) AS rows,
    (SELECT COUNT(DISTINCT review_id) FROM order_reviews) AS distinct_review_ids,
    (SELECT COUNT(DISTINCT order_id) FROM order_reviews) AS distinct_order_ids,
    (SELECT COUNT(*) FROM pairs WHERE rows_per_pair > 1) AS duplicate_review_order_pairs,
    (SELECT COUNT(*) FROM review_to_order WHERE orders_per_review > 1)
        AS review_ids_with_multiple_orders,
    (SELECT COUNT(*) FROM order_to_review WHERE reviews_per_order > 1)
        AS orders_with_multiple_review_ids,
    (SELECT COUNT(*)
     FROM orders o LEFT JOIN order_reviews r USING (order_id)
     WHERE r.order_id IS NULL) AS orders_without_reviews,
    (SELECT COUNT(*)
     FROM order_reviews r LEFT JOIN orders o USING (order_id)
     WHERE o.order_id IS NULL) AS review_rows_without_order;

-- 8.2 Score / timestamp integrity and delivery timing
WITH delivered_reviews AS (
    SELECT
        r.*,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    FROM order_reviews r
    JOIN orders o USING (order_id)
    WHERE o.order_delivered_customer_date IS NOT NULL
)
SELECT
    MIN(review_score) AS min_review_score,
    MAX(review_score) AS max_review_score,
    COUNT(*) FILTER (WHERE review_score NOT BETWEEN 1 AND 5) AS invalid_review_scores,
    COUNT(*) FILTER (WHERE review_creation_date IS NULL) AS null_review_creation_date,
    COUNT(*) FILTER (WHERE review_answer_timestamp IS NULL) AS null_review_answer_timestamp,
    COUNT(*) FILTER (WHERE review_answer_timestamp < review_creation_date) AS answer_before_creation,
    (SELECT COUNT(*)
     FROM delivered_reviews
     WHERE CAST(review_creation_date AS DATE)
           < CAST(order_delivered_customer_date AS DATE)) AS pre_delivery_review_rows,
    (SELECT COUNT(*)
     FROM delivered_reviews
     WHERE CAST(review_creation_date AS DATE)
           < CAST(order_delivered_customer_date AS DATE)
       AND order_delivered_customer_date > order_estimated_delivery_date)
        AS pre_delivery_reviews_late_delivery
FROM order_reviews;

-- 8.3 Latest-review determinism for order-level review metrics
WITH ranked AS (
    SELECT
        order_id,
        review_id,
        review_score,
        review_creation_date,
        review_answer_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY review_answer_timestamp DESC,
                     review_creation_date DESC,
                     review_id DESC
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY order_id, review_answer_timestamp, review_creation_date
        ) AS timestamp_ties
    FROM order_reviews
),
multi_review AS (
    SELECT order_id
    FROM order_reviews
    GROUP BY order_id
    HAVING COUNT(DISTINCT review_id) > 1
)
SELECT
    (SELECT COUNT(*) FROM multi_review) AS multi_review_orders,
    (SELECT COUNT(*)
     FROM (
         SELECT r.order_id
         FROM order_reviews r
         JOIN multi_review m USING (order_id)
         GROUP BY r.order_id
         HAVING COUNT(DISTINCT review_score) > 1
     )) AS multi_review_orders_with_score_change,
    COUNT(DISTINCT order_id) FILTER (WHERE timestamp_ties > 1)
        AS orders_with_timestamp_ties,
    COUNT(DISTINCT order_id) FILTER (WHERE rn = 1)
        AS orders_with_unique_latest_review
FROM ranked;


-- ============================================================
-- 9. Cross-Table Coverage / Final Window Validation
-- ============================================================

-- 9.1 Aggregate coverage
SELECT
    COUNT(*) AS analysis_orders,
    COUNT(*) FILTER (WHERE c.customer_id IS NOT NULL) AS orders_with_customer,
    COUNT(*) FILTER (WHERE i.order_id IS NOT NULL) AS orders_with_items,
    COUNT(*) FILTER (WHERE p.order_id IS NOT NULL) AS orders_with_payments,
    COUNT(*) FILTER (WHERE r.order_id IS NOT NULL) AS orders_with_reviews
FROM analysis_orders o
LEFT JOIN customers c USING (customer_id)
LEFT JOIN (SELECT DISTINCT order_id FROM order_items) i USING (order_id)
LEFT JOIN (SELECT DISTINCT order_id FROM order_payments) p USING (order_id)
LEFT JOIN (SELECT DISTINCT order_id FROM order_reviews) r USING (order_id);

-- 9.2 Monthly coverage stability
SELECT
    STRFTIME(DATE_TRUNC('month', o.order_purchase_timestamp), '%Y-%m') AS month,
    COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE i.order_id IS NOT NULL) / COUNT(*), 2)
        AS item_coverage_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE p.order_id IS NOT NULL) / COUNT(*), 2)
        AS payment_coverage_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.order_id IS NOT NULL) / COUNT(*), 2)
        AS review_coverage_pct
FROM analysis_orders o
LEFT JOIN (SELECT DISTINCT order_id FROM order_items) i USING (order_id)
LEFT JOIN (SELECT DISTINCT order_id FROM order_payments) p USING (order_id)
LEFT JOIN (SELECT DISTINCT order_id FROM order_reviews) r USING (order_id)
GROUP BY 1
ORDER BY 1;