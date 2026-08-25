-- ============================================================
-- Olist Diagnostic Analysis: Category Opportunity
-- ============================================================

-- ============================================================
-- 0. Sources
-- ============================================================

CREATE OR REPLACE TEMP VIEW item_base AS
SELECT *
FROM read_parquet('data/processed/item_base.parquet');


-- ============================================================
-- 1. Category Scale
-- ============================================================

-- Objective:
--   Identify categories with meaningful economic scale before
--   evaluating growth.
--
-- Metrics:
--   Merchandise GMV = SUM(merchandise_value)
--   Orders          = COUNT(DISTINCT order_id)
--   Customers       = COUNT(DISTINCT customer_unique_id)

SELECT
    product_category_name_english AS category,

    ROUND(
        SUM(merchandise_value),
        2
    ) AS merchandise_gmv,

    COUNT(DISTINCT order_id) AS orders,

    COUNT(DISTINCT customer_unique_id) AS customers,

    ROUND(
        SUM(merchandise_value)
        / NULLIF(COUNT(DISTINCT order_id), 0),
        2
    ) AS aov,

    ROUND(
        100.0 * SUM(merchandise_value)
        / SUM(SUM(merchandise_value)) OVER (),
        2
    ) AS gmv_share_pct

FROM item_base

GROUP BY category

ORDER BY merchandise_gmv DESC

LIMIT 20;


-- ============================================================
-- 2. Category Growth
-- ============================================================

-- Objective:
--   Identify categories that combine meaningful economic scale
--   with positive year-over-year growth.
--
-- Comparable periods:
--   Prior period:   2017-02-01 <= purchase < 2017-09-01
--   Current period: 2018-02-01 <= purchase < 2018-09-01
--
-- The same calendar months are compared to reduce seasonal bias.


-- ============================================================
-- 2.1 Comparable-Period Category Metrics
-- ============================================================

CREATE OR REPLACE TEMP VIEW category_comparable_growth AS
SELECT
    product_category_name_english AS category,

    ROUND(
        SUM(merchandise_value) FILTER (
            WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
              AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
        ),
        2
    ) AS gmv_2017_feb_aug,

    ROUND(
        SUM(merchandise_value) FILTER (
            WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
              AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
        ),
        2
    ) AS gmv_2018_feb_aug,

    COUNT(DISTINCT order_id) FILTER (
        WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
          AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
    ) AS orders_2017_feb_aug,

    COUNT(DISTINCT order_id) FILTER (
        WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
          AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
    ) AS orders_2018_feb_aug

FROM item_base
GROUP BY category;


-- ============================================================
-- 2.2 Scale x Growth
-- ============================================================

SELECT
    category,

    gmv_2017_feb_aug,
    gmv_2018_feb_aug,

    ROUND(
        gmv_2018_feb_aug - gmv_2017_feb_aug,
        2
    ) AS absolute_gmv_growth,

    ROUND(
        100.0
        * (gmv_2018_feb_aug - gmv_2017_feb_aug)
        / NULLIF(gmv_2017_feb_aug, 0),
        2
    ) AS gmv_growth_pct,

    orders_2017_feb_aug,
    orders_2018_feb_aug,

    ROUND(
        100.0
        * (orders_2018_feb_aug - orders_2017_feb_aug)
        / NULLIF(orders_2017_feb_aug, 0),
        2
    ) AS order_growth_pct

FROM category_comparable_growth

WHERE gmv_2017_feb_aug IS NOT NULL
  AND gmv_2018_feb_aug IS NOT NULL

ORDER BY gmv_2018_feb_aug DESC

LIMIT 20;


-- ============================================================
-- 3. Category Relative Growth / Market Share Shift
-- ============================================================

-- Objective:
--   Distinguish categories that merely grew with the overall market
--   from categories that gained economic importance within the market.


CREATE OR REPLACE TEMP VIEW market_comparable_growth AS
SELECT
    ROUND(
        SUM(merchandise_value) FILTER (
            WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
              AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
        ),
        2
    ) AS market_gmv_2017_feb_aug,

    ROUND(
        SUM(merchandise_value) FILTER (
            WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
              AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
        ),
        2
    ) AS market_gmv_2018_feb_aug

FROM item_base;


SELECT
    c.category,

    c.gmv_2018_feb_aug,

    ROUND(
        100.0
        * (c.gmv_2018_feb_aug - c.gmv_2017_feb_aug)
        / NULLIF(c.gmv_2017_feb_aug, 0),
        2
    ) AS category_gmv_growth_pct,

    ROUND(
        100.0
        * (m.market_gmv_2018_feb_aug - m.market_gmv_2017_feb_aug)
        / NULLIF(m.market_gmv_2017_feb_aug, 0),
        2
    ) AS market_gmv_growth_pct,

    ROUND(
        100.0 * c.gmv_2017_feb_aug
        / NULLIF(m.market_gmv_2017_feb_aug, 0),
        2
    ) AS gmv_share_2017_pct,

    ROUND(
        100.0 * c.gmv_2018_feb_aug
        / NULLIF(m.market_gmv_2018_feb_aug, 0),
        2
    ) AS gmv_share_2018_pct,

    ROUND(
        100.0 * c.gmv_2018_feb_aug
            / NULLIF(m.market_gmv_2018_feb_aug, 0)
        -
        100.0 * c.gmv_2017_feb_aug
            / NULLIF(m.market_gmv_2017_feb_aug, 0),
        2
    ) AS gmv_share_change_pp

FROM category_comparable_growth c
CROSS JOIN market_comparable_growth m

WHERE c.gmv_2017_feb_aug IS NOT NULL
  AND c.gmv_2018_feb_aug IS NOT NULL

ORDER BY c.gmv_2018_feb_aug DESC

LIMIT 20;