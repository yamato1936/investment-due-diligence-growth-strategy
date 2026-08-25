-- ============================================================
-- Olist Diagnostic Analysis: Downside Risk
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


-- ============================================================
-- 1. Candidate Orders
-- ============================================================

-- Grain:
--   1 row = 1 candidate category x state x order
--
-- DISTINCT is required because an order may contain multiple items
-- belonging to the same category.

CREATE OR REPLACE TEMP VIEW candidate_orders AS
SELECT DISTINCT
    product_category_name_english AS category,
    customer_state,
    order_id
FROM item_base
WHERE
       (product_category_name_english = 'health_beauty'
        AND customer_state = 'SP')

    OR (product_category_name_english = 'watches_gifts'
        AND customer_state = 'SP')

    OR (product_category_name_english = 'housewares'
        AND customer_state = 'SP')

    OR (product_category_name_english = 'health_beauty'
        AND customer_state = 'MG')

    OR (product_category_name_english = 'watches_gifts'
        AND customer_state = 'RJ');


-- ============================================================
-- 2. Candidate Risk Metrics
-- ============================================================

-- Metrics:
--   Late delivery rate =
--       late orders / late-delivery-eligible orders
--
--   Low review rate =
--       review score <= 2 / review-eligible orders
--
--   Average review score =
--       canonical latest review, review-eligible orders only

SELECT
    c.category,
    c.customer_state,

    COUNT(*) AS orders,

    COUNT(*) FILTER (
        WHERE o.late_delivery_eligible
    ) AS late_delivery_eligible_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE o.late_delivery_eligible
              AND o.late_delivery_flag
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE o.late_delivery_eligible
            ),
            0
        ),
        2
    ) AS late_delivery_rate_pct,

    COUNT(*) FILTER (
        WHERE o.review_eligible
    ) AS review_eligible_orders,

    ROUND(
        AVG(o.review_score) FILTER (
            WHERE o.review_eligible
        ),
        2
    ) AS avg_review_score,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE o.review_eligible
              AND o.review_score <= 2
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE o.review_eligible
            ),
            0
        ),
        2
    ) AS low_review_rate_pct

FROM candidate_orders c
JOIN order_base o USING (order_id)

GROUP BY
    c.category,
    c.customer_state

ORDER BY
    c.category,
    c.customer_state;


-- ============================================================
-- 3. Candidate Risk Screening
-- ============================================================

SELECT
    c.category,
    c.customer_state,

    COUNT(*) AS orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE o.late_delivery_eligible
              AND o.late_delivery_flag
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE o.late_delivery_eligible
            ),
            0
        ),
        2
    ) AS late_delivery_rate_pct,

    ROUND(
        AVG(o.review_score) FILTER (
            WHERE o.review_eligible
        ),
        2
    ) AS avg_review_score,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE o.review_eligible
              AND o.review_score <= 2
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE o.review_eligible
            ),
            0
        ),
        2
    ) AS low_review_rate_pct

FROM candidate_orders c
JOIN order_base o USING (order_id)

GROUP BY
    c.category,
    c.customer_state

ORDER BY
    c.category,
    c.customer_state;


-- ============================================================
-- 3.1 Late Delivery Risk
-- ============================================================

SELECT
    c.category,
    c.customer_state,

    COUNT(*) FILTER (
        WHERE o.late_delivery_eligible
    ) AS eligible_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE o.late_delivery_eligible
              AND o.late_delivery_flag
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE o.late_delivery_eligible
            ),
            0
        ),
        2
    ) AS late_delivery_rate_pct

FROM candidate_orders c
JOIN order_base o USING (order_id)

GROUP BY
    c.category,
    c.customer_state

ORDER BY
    c.category,
    c.customer_state;


-- ============================================================
-- 4. Risk Benchmark
-- ============================================================

-- Objective:
--   Compare shortlisted opportunities with the overall platform
--   baseline using identical metric definitions and denominators.


WITH market_risk AS (
    SELECT
        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE late_delivery_eligible
                  AND late_delivery_flag
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE late_delivery_eligible
                ),
                0
            ),
            2
        ) AS market_late_delivery_rate_pct,

        ROUND(
            AVG(review_score) FILTER (
                WHERE review_eligible
            ),
            2
        ) AS market_avg_review_score,

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE review_eligible
                  AND review_score <= 2
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE review_eligible
                ),
                0
            ),
            2
        ) AS market_low_review_rate_pct

    FROM order_base
),

candidate_risk AS (
    SELECT
        c.category,
        c.customer_state,

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE o.late_delivery_eligible
                  AND o.late_delivery_flag
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE o.late_delivery_eligible
                ),
                0
            ),
            2
        ) AS late_delivery_rate_pct,

        ROUND(
            AVG(o.review_score) FILTER (
                WHERE o.review_eligible
            ),
            2
        ) AS avg_review_score,

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE o.review_eligible
                  AND o.review_score <= 2
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE o.review_eligible
                ),
                0
            ),
            2
        ) AS low_review_rate_pct

    FROM candidate_orders c
    JOIN order_base o USING (order_id)

    GROUP BY
        c.category,
        c.customer_state
)

SELECT
    c.category,
    c.customer_state,

    c.late_delivery_rate_pct,
    m.market_late_delivery_rate_pct,

    ROUND(
        c.late_delivery_rate_pct
        - m.market_late_delivery_rate_pct,
        2
    ) AS late_delivery_vs_market_pp,

    c.avg_review_score,
    m.market_avg_review_score,

    c.low_review_rate_pct,
    m.market_low_review_rate_pct,

    ROUND(
        c.low_review_rate_pct
        - m.market_low_review_rate_pct,
        2
    ) AS low_review_vs_market_pp

FROM candidate_risk c
CROSS JOIN market_risk m

ORDER BY
    c.category,
    c.customer_state;


-- ============================================================
-- 5. Seller Concentration Risk
-- ============================================================

-- Objective:
--   Determine whether current-period GMV in shortlisted opportunities
--   depends excessively on a small number of sellers.
--
-- Period:
--   2018-02-01 <= purchase < 2018-09-01
--
-- Metrics:
--   seller_count
--   top_1_seller_gmv_share_pct
--   top_3_sellers_gmv_share_pct


-- ============================================================
-- 5.1 Seller-Level GMV
-- ============================================================

CREATE OR REPLACE TEMP VIEW candidate_seller_gmv AS
SELECT
    product_category_name_english AS category,
    customer_state,
    seller_id,

    SUM(merchandise_value) AS seller_gmv

FROM item_base

WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
  AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'

  AND (
         (product_category_name_english = 'health_beauty'
          AND customer_state = 'SP')

      OR (product_category_name_english = 'health_beauty'
          AND customer_state = 'MG')

      OR (product_category_name_english = 'housewares'
          AND customer_state = 'SP')

      OR (product_category_name_english = 'watches_gifts'
          AND customer_state = 'SP')

      OR (product_category_name_english = 'watches_gifts'
          AND customer_state = 'RJ')
  )

GROUP BY
    product_category_name_english,
    customer_state,
    seller_id;


-- ============================================================
-- 5.2 Seller Ranking
-- ============================================================

CREATE OR REPLACE TEMP VIEW candidate_seller_rank AS
SELECT
    category,
    customer_state,
    seller_id,
    seller_gmv,

    ROW_NUMBER() OVER (
        PARTITION BY category, customer_state
        ORDER BY seller_gmv DESC
    ) AS seller_rank,

    SUM(seller_gmv) OVER (
        PARTITION BY category, customer_state
    ) AS total_gmv

FROM candidate_seller_gmv;


-- ============================================================
-- 5.3 Concentration Screening
-- ============================================================

SELECT
    category,
    customer_state,

    COUNT(*) AS seller_count,

    ROUND(
        MAX(
            CASE
                WHEN seller_rank = 1
                THEN 100.0 * seller_gmv / NULLIF(total_gmv, 0)
            END
        ),
        2
    ) AS top_1_seller_gmv_share_pct,

    ROUND(
        SUM(
            CASE
                WHEN seller_rank <= 3
                THEN seller_gmv
                ELSE 0
            END
        )
        * 100.0
        / NULLIF(MAX(total_gmv), 0),
        2
    ) AS top_3_sellers_gmv_share_pct

FROM candidate_seller_rank

GROUP BY
    category,
    customer_state

ORDER BY
    category,
    customer_state;