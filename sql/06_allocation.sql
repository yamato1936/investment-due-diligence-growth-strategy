-- ============================================================
-- Olist Investment Allocation
-- ============================================================
-- Inputs are generated mechanically by sql/04 and sql/05.
-- Allocation remains a relative priority score, not ROI / IRR.
-- ============================================================

CREATE OR REPLACE TEMP VIEW opportunity_candidates AS
SELECT *
FROM read_parquet('data/processed/opportunity_candidates.parquet');

CREATE OR REPLACE TEMP VIEW candidate_risk AS
SELECT *
FROM read_parquet('data/processed/candidate_risk.parquet');

-- ============================================================
-- 1. Eligible candidate universe
-- ============================================================

CREATE OR REPLACE TEMP VIEW allocation_inputs AS
SELECT
    o.category,
    o.customer_state,
    o.gmv_prior,
    o.gmv_current,
    o.orders_current,
    o.absolute_gmv_growth,
    o.gmv_growth_pct,
    o.gmv_share_change_pp,
    r.late_delivery_rate,
    r.market_late_delivery_rate,
    r.avg_review_score,
    r.low_review_rate,
    r.market_low_review_rate,
    r.seller_count,
    r.top3_share,
    r.risk_eligible
FROM opportunity_candidates o
JOIN candidate_risk r USING (category, customer_state);

-- ============================================================
-- 2. Baseline heuristic score
-- ============================================================
-- Score = GMV^0.5 * DeltaGMV^0.5 * (1 - Top3Share)^1
--
-- This is an explainable prioritization heuristic. It is not claimed
-- to be a structural return model. Specification uncertainty is tested
-- separately in sql/07_uncertainty.sql.

CREATE OR REPLACE TEMP VIEW allocation_scores AS
SELECT
    *,
    CASE
        WHEN risk_eligible
         AND gmv_current > 0
         AND absolute_gmv_growth > 0
        THEN POWER(gmv_current, 0.5)
           * POWER(absolute_gmv_growth, 0.5)
           * POWER(1.0 - top3_share, 1.0)
        ELSE 0
    END AS adjusted_score
FROM allocation_inputs;

-- ============================================================
-- 3. Final recommendation: top 5 eligible segments
-- ============================================================
-- The number five is a decision-output constraint for a concise
-- portfolio recommendation, not a manually selected segment list.

CREATE OR REPLACE TEMP VIEW ranked_allocation AS
SELECT
    *,
    ROW_NUMBER() OVER (
        ORDER BY adjusted_score DESC, gmv_current DESC, category, customer_state
    ) AS priority_rank
FROM allocation_scores
WHERE risk_eligible;

CREATE OR REPLACE TEMP VIEW final_allocation AS
SELECT
    *,
    100.0 * adjusted_score
      / NULLIF(SUM(adjusted_score) OVER (), 0) AS allocation_pct
FROM ranked_allocation
WHERE priority_rank <= 5;

SELECT
    priority_rank,
    category,
    customer_state,
    ROUND(gmv_current, 2) AS gmv_current,
    ROUND(absolute_gmv_growth, 2) AS absolute_gmv_growth,
    ROUND(gmv_growth_pct, 2) AS gmv_growth_pct,
    ROUND(100 * late_delivery_rate, 2) AS late_delivery_rate_pct,
    ROUND(100 * low_review_rate, 2) AS low_review_rate_pct,
    seller_count,
    ROUND(100 * top3_share, 2) AS top3_seller_gmv_share_pct,
    ROUND(adjusted_score, 2) AS adjusted_score,
    ROUND(allocation_pct, 2) AS allocation_pct
FROM final_allocation
ORDER BY priority_rank;

-- Validation: allocation sums to 100% across the selected portfolio.
SELECT
    COUNT(*) AS selected_segments,
    ROUND(SUM(allocation_pct), 6) AS total_allocation_pct
FROM final_allocation;

COPY (
    SELECT *
    FROM final_allocation
    ORDER BY priority_rank
)
TO 'data/processed/allocation_recommendation.parquet'
(FORMAT PARQUET);
