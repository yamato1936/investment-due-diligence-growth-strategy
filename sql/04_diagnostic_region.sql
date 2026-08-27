-- ============================================================
-- Olist Diagnostic Analysis: Regional Opportunity
-- ============================================================
-- Purpose:
--   Evaluate every category x customer_state pair using one
--   reproducible screening rule. No manually curated candidate list.
--
-- Comparable periods:
--   Prior:   2017-02-01 <= purchase < 2017-09-01
--   Current: 2018-02-01 <= purchase < 2018-09-01
-- ============================================================

CREATE OR REPLACE TEMP VIEW item_base AS
SELECT *
FROM read_parquet('data/processed/item_base.parquet');

-- ============================================================
-- 1. Comparable-period metrics for ALL category x state pairs
-- ============================================================

CREATE OR REPLACE TEMP VIEW category_state_comparable AS
SELECT
    product_category_name_english AS category,
    customer_state,

    SUM(merchandise_value) FILTER (
        WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
          AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
    ) AS gmv_prior,

    SUM(merchandise_value) FILTER (
        WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
          AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
    ) AS gmv_current,

    COUNT(DISTINCT order_id) FILTER (
        WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
          AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
    ) AS orders_prior,

    COUNT(DISTINCT order_id) FILTER (
        WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
          AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
    ) AS orders_current

FROM item_base
GROUP BY 1, 2;

CREATE OR REPLACE TEMP VIEW market_comparable AS
SELECT
    SUM(merchandise_value) FILTER (
        WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
          AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
    ) AS market_gmv_prior,

    SUM(merchandise_value) FILTER (
        WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
          AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
    ) AS market_gmv_current
FROM item_base;

CREATE OR REPLACE TEMP VIEW category_state_opportunity AS
SELECT
    c.category,
    c.customer_state,
    c.gmv_prior,
    c.gmv_current,
    c.orders_prior,
    c.orders_current,
    c.gmv_current - c.gmv_prior AS absolute_gmv_growth,
    100.0 * (c.gmv_current - c.gmv_prior) / NULLIF(c.gmv_prior, 0) AS gmv_growth_pct,
    100.0 * c.gmv_prior / NULLIF(m.market_gmv_prior, 0) AS gmv_share_prior_pct,
    100.0 * c.gmv_current / NULLIF(m.market_gmv_current, 0) AS gmv_share_current_pct,
    100.0 * c.gmv_current / NULLIF(m.market_gmv_current, 0)
      - 100.0 * c.gmv_prior / NULLIF(m.market_gmv_prior, 0) AS gmv_share_change_pp
FROM category_state_comparable c
CROSS JOIN market_comparable m
WHERE c.gmv_prior > 0
  AND c.gmv_current > 0;

-- ============================================================
-- 2. Mechanical screening rule
-- ============================================================
-- Rule is intentionally simple and inspectable:
--   - observed in both comparable periods
--   - current GMV >= 95th percentile across observed segments
--   - current orders >= 100
--   - positive absolute GMV growth
--   - positive GMV-share change vs market
--
-- The 95th-percentile and 100-order thresholds are assumptions and
-- are tested explicitly in sql/07_uncertainty.sql.

CREATE OR REPLACE TEMP VIEW opportunity_thresholds AS
SELECT
    QUANTILE_CONT(gmv_current, 0.95) AS min_current_gmv,
    100::BIGINT AS min_current_orders
FROM category_state_opportunity;

CREATE OR REPLACE TEMP VIEW opportunity_screen AS
SELECT
    o.*,
    t.min_current_gmv,
    t.min_current_orders,
    (
        o.gmv_current >= t.min_current_gmv
        AND o.orders_current >= t.min_current_orders
        AND o.absolute_gmv_growth > 0
        AND o.gmv_share_change_pp > 0
    ) AS opportunity_eligible
FROM category_state_opportunity o
CROSS JOIN opportunity_thresholds t;

SELECT
    category,
    customer_state,
    ROUND(gmv_current, 2) AS gmv_current,
    orders_current,
    ROUND(absolute_gmv_growth, 2) AS absolute_gmv_growth,
    ROUND(gmv_growth_pct, 2) AS gmv_growth_pct,
    ROUND(gmv_share_change_pp, 4) AS gmv_share_change_pp,
    ROUND(min_current_gmv, 2) AS min_current_gmv,
    opportunity_eligible
FROM opportunity_screen
ORDER BY opportunity_eligible DESC, gmv_current DESC;

COPY (
    SELECT *
    FROM opportunity_screen
    WHERE opportunity_eligible
)
TO 'data/processed/opportunity_candidates.parquet'
(FORMAT PARQUET);
