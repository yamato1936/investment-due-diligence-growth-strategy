-- ============================================================
-- Olist Investment Allocation
-- ============================================================
-- Purpose:
--   Convert diagnostic findings into a transparent relative
--   resource-allocation recommendation across shortlisted
--   category x region segments.
--
-- Decision logic:
--
--   1. Eligibility gate
--      - Positive absolute GMV growth
--      - Exclude a segment when BOTH late-delivery rate and
--        low-review rate are worse than the market benchmark
--
--   2. Opportunity score
--
--      Base Score =
--          SQRT(Current GMV * Absolute GMV Growth)
--
--   3. Seller-concentration adjustment
--
--      Diversification Multiplier =
--          1 - Top-3 Seller GMV Share
--
--      Adjusted Score =
--          Base Score * Diversification Multiplier
--
--   4. Allocation
--
--      Allocation % =
--          Adjusted Score / Sum(Adjusted Scores of Eligible Segments)
--
-- Important:
--   Allocation % is a relative resource-allocation priority.
--   It is NOT an expected financial return, IRR, or ROI.
--
-- Comparable periods:
--   Prior:   2017-02-01 <= purchase < 2017-09-01
--   Current: 2018-02-01 <= purchase < 2018-09-01
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
-- 1. Candidate Segments
-- ============================================================

-- Shortlist established during category, regional, and risk
-- diagnostics.
--
-- Grain:
--   1 row = 1 candidate category x customer_state

CREATE OR REPLACE TEMP VIEW candidate_segments AS
SELECT *
FROM (
    VALUES
        ('health_beauty', 'SP'),
        ('health_beauty', 'MG'),
        ('housewares',    'SP'),
        ('watches_gifts', 'SP'),
        ('watches_gifts', 'RJ')
) AS t(category, customer_state);


-- ============================================================
-- 2. Opportunity Metrics
-- ============================================================

-- Current scale and comparable-period absolute growth.

CREATE OR REPLACE TEMP VIEW candidate_opportunity AS
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
    ) AS gmv_2018_feb_aug

FROM item_base i

JOIN candidate_segments c
    ON i.product_category_name_english = c.category
   AND i.customer_state = c.customer_state

GROUP BY
    i.product_category_name_english,
    i.customer_state;


CREATE OR REPLACE TEMP VIEW candidate_growth AS
SELECT
    category,
    customer_state,

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
    ) AS gmv_growth_pct

FROM candidate_opportunity;


-- ============================================================
-- 3. Candidate Order Population
-- ============================================================

-- Item-level candidate identification is reduced to order grain
-- before joining order-level delivery and review metrics.
--
-- Grain:
--   1 row = 1 category x state x order

CREATE OR REPLACE TEMP VIEW candidate_orders AS
SELECT DISTINCT
    i.product_category_name_english AS category,
    i.customer_state,
    i.order_id

FROM item_base i

JOIN candidate_segments c
    ON i.product_category_name_english = c.category
   AND i.customer_state = c.customer_state;


-- ============================================================
-- 4. Market Risk Benchmark
-- ============================================================

CREATE OR REPLACE TEMP VIEW market_risk AS
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

FROM order_base;


-- ============================================================
-- 5. Candidate Risk Metrics
-- ============================================================

CREATE OR REPLACE TEMP VIEW candidate_risk AS
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
    c.customer_state;


-- ============================================================
-- 6. Seller Concentration
-- ============================================================

-- Concentration is measured using current comparable-period GMV.

CREATE OR REPLACE TEMP VIEW candidate_seller_gmv AS
SELECT
    i.product_category_name_english AS category,
    i.customer_state,
    i.seller_id,

    SUM(i.merchandise_value) AS seller_gmv

FROM item_base i

JOIN candidate_segments c
    ON i.product_category_name_english = c.category
   AND i.customer_state = c.customer_state

WHERE i.order_purchase_timestamp >= TIMESTAMP '2018-02-01'
  AND i.order_purchase_timestamp <  TIMESTAMP '2018-09-01'

GROUP BY
    i.product_category_name_english,
    i.customer_state,
    i.seller_id;


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


CREATE OR REPLACE TEMP VIEW candidate_concentration AS
SELECT
    category,
    customer_state,

    COUNT(*) AS seller_count,

    ROUND(
        MAX(
            CASE
                WHEN seller_rank = 1
                THEN 100.0 * seller_gmv
                     / NULLIF(total_gmv, 0)
            END
        ),
        2
    ) AS top_1_seller_gmv_share_pct,

    ROUND(
        100.0
        * SUM(
            CASE
                WHEN seller_rank <= 3
                THEN seller_gmv
                ELSE 0
            END
        )
        / NULLIF(MAX(total_gmv), 0),
        2
    ) AS top_3_sellers_gmv_share_pct

FROM candidate_seller_rank

GROUP BY
    category,
    customer_state;


-- ============================================================
-- 7. Investment Eligibility
-- ============================================================

-- Eligibility rules:
--
--   1. Absolute GMV growth must be positive.
--
--   2. Exclude only when BOTH operational risk measures are
--      worse than the overall market:
--
--        late_delivery_rate > market
--        AND
--        low_review_rate > market
--
-- This prevents one isolated KPI from automatically eliminating
-- an otherwise attractive segment.

CREATE OR REPLACE TEMP VIEW allocation_inputs AS
SELECT
    g.category,
    g.customer_state,

    -- Opportunity
    g.gmv_2017_feb_aug,
    g.gmv_2018_feb_aug,
    g.absolute_gmv_growth,
    g.gmv_growth_pct,

    -- Operational risk
    r.late_delivery_rate_pct,
    m.market_late_delivery_rate_pct,

    ROUND(
        r.late_delivery_rate_pct
        - m.market_late_delivery_rate_pct,
        2
    ) AS late_delivery_vs_market_pp,

    r.avg_review_score,
    m.market_avg_review_score,

    r.low_review_rate_pct,
    m.market_low_review_rate_pct,

    ROUND(
        r.low_review_rate_pct
        - m.market_low_review_rate_pct,
        2
    ) AS low_review_vs_market_pp,

    -- Supply concentration
    s.seller_count,
    s.top_1_seller_gmv_share_pct,
    s.top_3_sellers_gmv_share_pct,

    -- Eligibility
    CASE
        WHEN g.absolute_gmv_growth <= 0
            THEN FALSE

        WHEN r.late_delivery_rate_pct
                > m.market_late_delivery_rate_pct
         AND r.low_review_rate_pct
                > m.market_low_review_rate_pct
            THEN FALSE

        ELSE TRUE
    END AS eligible_flag

FROM candidate_growth g

JOIN candidate_risk r
    ON g.category = r.category
   AND g.customer_state = r.customer_state

JOIN candidate_concentration s
    ON g.category = s.category
   AND g.customer_state = s.customer_state

CROSS JOIN market_risk m;


-- ============================================================
-- 8. Allocation Score
-- ============================================================

-- Base Score:
--
--   SQRT(Current GMV * Absolute GMV Growth)
--
-- Diversification Multiplier:
--
--   1 - Top-3 Seller GMV Share
--
-- Adjusted Score:
--
--   Base Score * Diversification Multiplier
--
-- Ineligible candidates receive an adjusted score of zero.

CREATE OR REPLACE TEMP VIEW allocation_scores AS
SELECT
    *,

    CASE
        WHEN eligible_flag
         AND gmv_2018_feb_aug > 0
         AND absolute_gmv_growth > 0
        THEN SQRT(
            gmv_2018_feb_aug
            * absolute_gmv_growth
        )
        ELSE 0
    END AS base_score,

    CASE
        WHEN eligible_flag
        THEN 1.0 - (
            top_3_sellers_gmv_share_pct / 100.0
        )
        ELSE 0
    END AS diversification_multiplier

FROM allocation_inputs;


CREATE OR REPLACE TEMP VIEW final_allocation AS
SELECT
    *,

    base_score
        * diversification_multiplier
        AS adjusted_score

FROM allocation_scores;


-- ============================================================
-- 9. Final Resource Allocation
-- ============================================================

-- Allocation percentages sum to 100% across eligible segments.
--
-- This is a relative allocation priority based on observed
-- marketplace evidence, not a financial-return forecast.

SELECT
    category,
    customer_state,

    eligible_flag,

    gmv_2018_feb_aug,
    absolute_gmv_growth,
    gmv_growth_pct,

    late_delivery_rate_pct,
    market_late_delivery_rate_pct,

    low_review_rate_pct,
    market_low_review_rate_pct,

    seller_count,
    top_3_sellers_gmv_share_pct,

    ROUND(
        base_score,
        2
    ) AS base_score,

    ROUND(
        diversification_multiplier,
        4
    ) AS diversification_multiplier,

    ROUND(
        adjusted_score,
        2
    ) AS adjusted_score,

    CASE
        WHEN eligible_flag
        THEN ROUND(
            100.0
            * adjusted_score
            / NULLIF(
                SUM(adjusted_score) OVER (),
                0
            ),
            2
        )
        ELSE 0
    END AS allocation_pct

FROM final_allocation

ORDER BY
    allocation_pct DESC,
    adjusted_score DESC;


-- ============================================================
-- 10. Allocation Validation
-- ============================================================

-- 10.1 Allocation must sum to approximately 100%

SELECT
    COUNT(*) AS candidate_segments,

    COUNT(*) FILTER (
        WHERE eligible_flag
    ) AS eligible_segments,

    COUNT(*) FILTER (
        WHERE NOT eligible_flag
    ) AS excluded_segments,

    ROUND(
        SUM(
            CASE
                WHEN eligible_flag
                THEN 100.0
                    * adjusted_score
                    / NULLIF(
                        (
                            SELECT SUM(adjusted_score)
                            FROM final_allocation
                        ),
                        0
                    )
                ELSE 0
            END
        ),
        2
    ) AS total_allocation_pct

FROM final_allocation;


-- ============================================================
-- 11. Sensitivity: No Seller-Concentration Adjustment
-- ============================================================

-- Compare the final ranking with a simpler allocation based only
-- on scale x absolute growth.
--
-- Large ranking changes would indicate that the recommendation
-- is highly sensitive to the seller-concentration assumption.

SELECT
    category,
    customer_state,

    eligible_flag,

    ROUND(
        100.0
        * base_score
        / NULLIF(
            SUM(base_score) FILTER (
                WHERE eligible_flag
            ) OVER (),
            0
        ),
        2
    ) AS allocation_without_concentration_pct,

    ROUND(
        100.0
        * adjusted_score
        / NULLIF(
            SUM(adjusted_score) OVER (),
            0
        ),
        2
    ) AS allocation_with_concentration_pct

FROM final_allocation

WHERE eligible_flag

ORDER BY
    allocation_with_concentration_pct DESC;


-- ============================================================
-- 12. Materialize Allocation Recommendation
-- ============================================================

COPY (
    SELECT
        category,
        customer_state,
        eligible_flag,

        gmv_2018_feb_aug,
        absolute_gmv_growth,
        gmv_growth_pct,

        late_delivery_rate_pct,
        low_review_rate_pct,

        seller_count,
        top_3_sellers_gmv_share_pct,

        adjusted_score,

        CASE
            WHEN eligible_flag
            THEN ROUND(
                100.0
                * adjusted_score
                / NULLIF(
                    SUM(adjusted_score) OVER (),
                    0
                ),
                2
            )
            ELSE 0
        END AS allocation_pct

    FROM final_allocation
)
TO 'data/processed/allocation_recommendation.parquet'
(FORMAT PARQUET);
