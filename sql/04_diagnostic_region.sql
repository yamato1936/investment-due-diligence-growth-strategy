-- ============================================================
-- Olist Diagnostic Analysis: Regional Opportunity
-- ============================================================

-- ============================================================
-- 0. Sources
-- ============================================================

CREATE OR REPLACE TEMP VIEW item_base AS
SELECT *
FROM read_parquet('data/processed/item_base.parquet');


-- ============================================================
-- 1. Candidate Category x State Scale
-- ============================================================

-- Objective:
--   Identify geographic concentrations within the shortlisted
--   investment candidate categories.
--
-- Candidate categories:
--   health_beauty
--   watches_gifts
--   housewares
--   auto
--   baby


SELECT
    product_category_name_english AS category,
    customer_state,

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
        / SUM(SUM(merchandise_value)) OVER (
            PARTITION BY product_category_name_english
        ),
        2
    ) AS category_gmv_share_pct

FROM item_base

WHERE product_category_name_english IN (
    'health_beauty',
    'watches_gifts',
    'housewares',
    'auto',
    'baby'
)

GROUP BY
    category,
    customer_state

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY category
    ORDER BY SUM(merchandise_value) DESC
) <= 5

ORDER BY
    category,
    merchandise_gmv DESC;


-- ============================================================
-- 2. Candidate Category x State Growth
-- ============================================================

-- Objective:
--   Identify regions that combine meaningful scale with positive
--   growth within the shortlisted investment categories.
--
-- Comparable periods:
--   Prior period:   2017-02-01 <= purchase < 2017-09-01
--   Current period: 2018-02-01 <= purchase < 2018-09-01


-- ============================================================
-- 2.1 Shortlisted Category-State Pairs
-- ============================================================

CREATE OR REPLACE TEMP VIEW candidate_category_states AS
SELECT
    category,
    customer_state
FROM (
    SELECT
        product_category_name_english AS category,
        customer_state,
        SUM(merchandise_value) AS merchandise_gmv,

        ROW_NUMBER() OVER (
            PARTITION BY product_category_name_english
            ORDER BY SUM(merchandise_value) DESC
        ) AS state_rank

    FROM item_base

    WHERE product_category_name_english IN (
        'health_beauty',
        'watches_gifts',
        'housewares',
        'auto',
        'baby'
    )

    GROUP BY
        product_category_name_english,
        customer_state
)
WHERE state_rank <= 5;


-- ============================================================
-- 2.2 Comparable-Period State Metrics
-- ============================================================

CREATE OR REPLACE TEMP VIEW category_state_growth AS
SELECT
    i.product_category_name_english AS category,
    i.customer_state,

    ROUND(
        SUM(i.merchandise_value) FILTER (
            WHERE i.order_purchase_timestamp >= TIMESTAMP '2017-02-01'
              AND i.order_purchase_timestamp <  TIMESTAMP '2017-09-01'
        ),
        2
    ) AS gmv_2017_feb_aug,

    ROUND(
        SUM(i.merchandise_value) FILTER (
            WHERE i.order_purchase_timestamp >= TIMESTAMP '2018-02-01'
              AND i.order_purchase_timestamp <  TIMESTAMP '2018-09-01'
        ),
        2
    ) AS gmv_2018_feb_aug,

    COUNT(DISTINCT i.order_id) FILTER (
        WHERE i.order_purchase_timestamp >= TIMESTAMP '2017-02-01'
          AND i.order_purchase_timestamp <  TIMESTAMP '2017-09-01'
    ) AS orders_2017_feb_aug,

    COUNT(DISTINCT i.order_id) FILTER (
        WHERE i.order_purchase_timestamp >= TIMESTAMP '2018-02-01'
          AND i.order_purchase_timestamp <  TIMESTAMP '2018-09-01'
    ) AS orders_2018_feb_aug

FROM item_base i

JOIN candidate_category_states c
    ON i.product_category_name_english = c.category
   AND i.customer_state = c.customer_state

GROUP BY
    i.product_category_name_english,
    i.customer_state;


-- ============================================================
-- 2.3 State Scale x Growth
-- ============================================================

SELECT
    category,
    customer_state,

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

    orders_2018_feb_aug,

    ROUND(
        100.0
        * (orders_2018_feb_aug - orders_2017_feb_aug)
        / NULLIF(orders_2017_feb_aug, 0),
        2
    ) AS order_growth_pct

FROM category_state_growth

WHERE gmv_2017_feb_aug IS NOT NULL
  AND gmv_2018_feb_aug IS NOT NULL

ORDER BY
    category,
    gmv_2018_feb_aug DESC;


-- ============================================================
-- 2.4 Regional Investment Screening
-- ============================================================

SELECT
    category,
    customer_state,
    gmv_2018_feb_aug,
    absolute_gmv_growth,
    gmv_growth_pct
FROM (
    SELECT
        category,
        customer_state,

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
        ) AS gmv_growth_pct

    FROM category_state_growth
)
ORDER BY
    category,
    gmv_2018_feb_aug DESC;


-- ============================================================
-- 2.5 Health & Beauty Regional Screening
-- ============================================================

SELECT
    category,
    customer_state,
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
    ) AS gmv_growth_pct

FROM category_state_growth

WHERE category = 'health_beauty'

ORDER BY gmv_2018_feb_aug DESC;