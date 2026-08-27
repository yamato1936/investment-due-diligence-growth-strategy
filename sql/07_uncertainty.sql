-- ============================================================
-- Olist Uncertainty & Robustness Analysis
-- ============================================================
-- Covers three uncertainty layers:
--   1. Sampling uncertainty for proportion KPIs (Wilson 95% CI)
--   2. Model-specification uncertainty for allocation ranking
--   3. Candidate-screen threshold sensitivity
-- ============================================================

CREATE OR REPLACE TEMP VIEW order_base AS
SELECT *
FROM read_parquet('data/processed/order_base.parquet');

CREATE OR REPLACE TEMP VIEW item_base AS
SELECT *
FROM read_parquet('data/processed/item_base.parquet');

CREATE OR REPLACE TEMP VIEW opportunity_candidates AS
SELECT *
FROM read_parquet('data/processed/opportunity_candidates.parquet');

CREATE OR REPLACE TEMP VIEW candidate_risk AS
SELECT *
FROM read_parquet('data/processed/candidate_risk.parquet');

CREATE OR REPLACE TEMP VIEW final_allocation AS
SELECT *
FROM read_parquet('data/processed/allocation_recommendation.parquet');

-- ============================================================
-- 1. Wilson 95% confidence intervals
-- ============================================================
-- For a binomial proportion p = k / n:
--
--   center = (p + z^2/(2n)) / (1 + z^2/n)
--   half   = z * sqrt(p(1-p)/n + z^2/(4n^2)) / (1 + z^2/n)
--
-- z = 1.959964 for a two-sided 95% CI.

CREATE OR REPLACE TEMP VIEW risk_ci_inputs AS
SELECT
    category,
    customer_state,
    late_k,
    late_n,
    low_review_k,
    review_n,
    late_delivery_rate,
    low_review_rate
FROM candidate_risk
WHERE risk_eligible;

CREATE OR REPLACE TEMP VIEW risk_ci AS
WITH constants AS (
    SELECT 1.959963984540054 AS z
),
calc AS (
    SELECT
        r.*,
        c.z,
        1.0 * late_k / NULLIF(late_n, 0) AS p_late,
        1.0 * low_review_k / NULLIF(review_n, 0) AS p_low
    FROM risk_ci_inputs r
    CROSS JOIN constants c
)
SELECT
    category,
    customer_state,
    late_n,
    late_k,
    late_delivery_rate,
    (
      (p_late + z*z/(2*late_n)) / (1 + z*z/late_n)
      - z * SQRT(p_late*(1-p_late)/late_n + z*z/(4*late_n*late_n))
        / (1 + z*z/late_n)
    ) AS late_ci_low,
    (
      (p_late + z*z/(2*late_n)) / (1 + z*z/late_n)
      + z * SQRT(p_late*(1-p_late)/late_n + z*z/(4*late_n*late_n))
        / (1 + z*z/late_n)
    ) AS late_ci_high,
    review_n,
    low_review_k,
    low_review_rate,
    (
      (p_low + z*z/(2*review_n)) / (1 + z*z/review_n)
      - z * SQRT(p_low*(1-p_low)/review_n + z*z/(4*review_n*review_n))
        / (1 + z*z/review_n)
    ) AS low_review_ci_low,
    (
      (p_low + z*z/(2*review_n)) / (1 + z*z/review_n)
      + z * SQRT(p_low*(1-p_low)/review_n + z*z/(4*review_n*review_n))
        / (1 + z*z/review_n)
    ) AS low_review_ci_high
FROM calc;

SELECT
    category,
    customer_state,
    ROUND(100 * late_delivery_rate, 2) AS late_delivery_rate_pct,
    ROUND(100 * late_ci_low, 2) AS late_ci_low_pct,
    ROUND(100 * late_ci_high, 2) AS late_ci_high_pct,
    ROUND(100 * low_review_rate, 2) AS low_review_rate_pct,
    ROUND(100 * low_review_ci_low, 2) AS low_review_ci_low_pct,
    ROUND(100 * low_review_ci_high, 2) AS low_review_ci_high_pct
FROM risk_ci
WHERE (category, customer_state) IN (
    SELECT category, customer_state FROM final_allocation
)
ORDER BY category, customer_state;

-- ============================================================
-- 2. Model-specification uncertainty
-- ============================================================
-- Score(alpha, beta, gamma) =
--   GMV^alpha * DeltaGMV^beta * (1 - Top3Share)^gamma
--
-- Grid:
--   alpha in {0.25, 0.50, 0.75, 1.00}
--   beta  in {0.25, 0.50, 0.75, 1.00}
--   gamma in {0.00, 0.50, 1.00, 1.50, 2.00}
-- Total = 80 specifications.

CREATE OR REPLACE TEMP VIEW spec_grid AS
SELECT * FROM (
    VALUES (0.25), (0.50), (0.75), (1.00)
) a(alpha)
CROSS JOIN (
    VALUES (0.25), (0.50), (0.75), (1.00)
) b(beta)
CROSS JOIN (
    VALUES (0.00), (0.50), (1.00), (1.50), (2.00)
) g(gamma);

CREATE OR REPLACE TEMP VIEW specification_scores AS
SELECT
    s.alpha,
    s.beta,
    s.gamma,
    o.category,
    o.customer_state,
    POWER(o.gmv_current, s.alpha)
      * POWER(o.absolute_gmv_growth, s.beta)
      * POWER(1.0 - r.top3_share, s.gamma) AS score
FROM opportunity_candidates o
JOIN candidate_risk r USING (category, customer_state)
CROSS JOIN spec_grid s
WHERE r.risk_eligible
  AND o.gmv_current > 0
  AND o.absolute_gmv_growth > 0;

CREATE OR REPLACE TEMP VIEW specification_ranks AS
SELECT
    *,
    ROW_NUMBER() OVER (
        PARTITION BY alpha, beta, gamma
        ORDER BY score DESC, category, customer_state
    ) AS rank_in_spec
FROM specification_scores;

SELECT
    category,
    customer_state,
    COUNT(*) AS specifications_evaluated,
    COUNT(*) FILTER (WHERE rank_in_spec = 1) AS rank1_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE rank_in_spec = 1) / COUNT(*),
        2
    ) AS rank1_share_pct,
    ROUND(AVG(rank_in_spec), 2) AS avg_rank,
    MIN(rank_in_spec) AS best_rank,
    MAX(rank_in_spec) AS worst_rank
FROM specification_ranks
GROUP BY 1, 2
ORDER BY rank1_share_pct DESC, avg_rank ASC;

-- ============================================================
-- 3. Candidate-screen threshold sensitivity
-- ============================================================
-- Rebuild the universe from all category x state pairs, then vary:
--   GMV percentile in {90, 92.5, 95, 97.5}
--   minimum current orders in {50, 100, 200}
-- Positive absolute growth and positive share change remain fixed.

CREATE OR REPLACE TEMP VIEW all_segment_comparable AS
WITH segment AS (
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
            WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
              AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
        ) AS orders_current
    FROM item_base
    GROUP BY 1, 2
),
market AS (
    SELECT
        SUM(merchandise_value) FILTER (
            WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
              AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
        ) AS market_prior,
        SUM(merchandise_value) FILTER (
            WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
              AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
        ) AS market_current
    FROM item_base
)
SELECT
    s.*,
    s.gmv_current - s.gmv_prior AS absolute_gmv_growth,
    100.0 * s.gmv_current / NULLIF(m.market_current, 0)
      - 100.0 * s.gmv_prior / NULLIF(m.market_prior, 0) AS gmv_share_change_pp
FROM segment s
CROSS JOIN market m
WHERE s.gmv_prior > 0
  AND s.gmv_current > 0;

CREATE OR REPLACE TEMP VIEW threshold_grid AS
SELECT * FROM (
    VALUES (0.900), (0.925), (0.950), (0.975)
) q(gmv_quantile)
CROSS JOIN (
    VALUES (50), (100), (200)
) n(min_orders);

CREATE OR REPLACE TEMP VIEW threshold_values AS
SELECT
    t.gmv_quantile,
    t.min_orders,
    QUANTILE_CONT(a.gmv_current, t.gmv_quantile) AS min_gmv
FROM threshold_grid t
CROSS JOIN all_segment_comparable a
GROUP BY 1, 2;

-- The risk screen is evaluated only for the baseline opportunity universe.
-- Therefore threshold sensitivity here tests the opportunity-screen stage;
-- operational eligibility remains a downstream gate in sql/05.

CREATE OR REPLACE TEMP VIEW threshold_candidates AS
SELECT
    v.gmv_quantile,
    v.min_orders,
    a.category,
    a.customer_state,
    a.gmv_current,
    a.absolute_gmv_growth,
    a.gmv_share_change_pp
FROM threshold_values v
JOIN all_segment_comparable a
  ON a.gmv_current >= v.min_gmv
 AND a.orders_current >= v.min_orders
 AND a.absolute_gmv_growth > 0
 AND a.gmv_share_change_pp > 0;

SELECT
    gmv_quantile,
    min_orders,
    COUNT(*) AS opportunity_candidates,
    MAX(CASE WHEN category = 'health_beauty' AND customer_state = 'SP' THEN 1 ELSE 0 END) AS health_beauty_sp_retained
FROM threshold_candidates
GROUP BY 1, 2
ORDER BY gmv_quantile, min_orders;

COPY (
    SELECT * FROM risk_ci
)
TO 'data/processed/risk_confidence_intervals.parquet'
(FORMAT PARQUET);

COPY (
    SELECT * FROM specification_ranks
)
TO 'data/processed/specification_ranks.parquet'
(FORMAT PARQUET);
