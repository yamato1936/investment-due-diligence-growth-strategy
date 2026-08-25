# Investment Decision — INVEST

## Decision

**INVEST — selectively, not market-wide.**

Brazilian e-commerce全体への均等配分ではなく、成長・顧客体験・seller diversificationが同時に確認されたsegmentへ重点配分する。

### Recommended Relative Allocation

| Priority | Segment | Allocation |
|---|---|---:|
| Core | health_beauty × SP | ~40% |
| Core | housewares × SP | ~25% |
| Higher-risk growth | watches_gifts × SP | ~20% |
| Expansion | health_beauty × MG | ~10–15% |
| Exclude | watches_gifts × RJ | 0% |

この配分率はfinancial return forecastではなく、**observed marketplace evidenceに基づくrelative resource-allocation priority**である。

---

## Evidence

市場全体は2017年に急拡大した一方、2018年にはorders / active customers / GMVの成長がplateauする兆候がある。

AOVには明確な上昇トレンドがなく、成長は主にcustomer acquisitionとorder volumeによって説明される。

また、returning customersは月間active customersの約2〜3%に留まり、完全月cohortにおける90-day repeat rateは加重平均で約 **2.34%** だった。

したがって、marketplace全体としては新規顧客獲得への依存が大きい。

一方、成長はsegment間で均一ではない。

最有力の **health_beauty × SP** は以下の特徴を持つ。

- 2018 Feb–Aug GMV: 275,923
- Comparable-period absolute GMV growth: +205,740
- GMV growth: +293%
- Late delivery rate: 7.10%
- Market late delivery rate: 8.17%
- Average review score: 4.28
- Low-review rate: 10.34%
- Market low-review rate: 14.62%
- Sellers: 303
- Top-3 seller GMV share: 21.78%

したがって、health_beauty × SPでは、

**scale + growth + customer experience + supply diversification**

の4条件が同時に成立している。

さらに、seller concentration adjustmentの有無を比較しても、health_beauty × SPはallocation順位1位を維持した。

---

## Downside

### 1. Acquisition Dependence

最大のmarket-level riskは新規顧客獲得への依存である。

短期repeat purchasingが弱いため、新規顧客流入が鈍化するとorders / GMVもそのまま鈍化する可能性がある。

実際、2018年にはmarket-wide growth slowdownの兆候が確認されている。

### 2. Seller Concentration

segment-levelではseller concentrationにも注意が必要である。

特に **watches_gifts × SP** は、

- Top-1 seller GMV share: 18.45%
- Top-3 seller GMV share: 44.66%

と比較的集中度が高い。

seller concentration adjustmentを行うとallocationは、

- Without concentration adjustment: 28.79%
- With concentration adjustment: 22.12%

まで低下する。

したがって、このsegmentのallocation recommendationはseller concentration assumptionに比較的敏感である。

### 3. Operational Risk

**watches_gifts × RJ** は以下の点でmarket benchmarkを明確に下回る。

- Late delivery rate: 14.65%
- Market late delivery rate: 8.17%
- Low-review rate: 22.42%
- Market low-review rate: 14.62%
- Average review score: 3.80
- Top-3 seller GMV share: 41.87%

そのため、高いGMV growthが確認されていても現時点ではallocation対象から除外する。

---

## Assumptions and Limitations

Olist datasetには以下の変数が含まれていない。

- take rate
- net revenue
- gross margin
- CAC
- marketing spend
- seller acquisition cost
- incremental investment requirement
- cash flow

したがって、ROI / IRR / expected profitを直接推定することはできない。

今回のallocationは、

> marketplace growth opportunityとoperational qualityに基づき、どのsegmentへ相対的に資源を優先配分すべきか

を評価したものである。

これはfinancial due diligenceを代替するものではない。

また、customer analysisにおけるfirst observed purchaseはdataset上の初回購入であり、顧客の真の生涯初回購入とは限らない。

---

## Withdrawal Triggers

### 1. Growth Thesis Breaks

候補segmentのcomparable-period absolute GMV growthが、

\[
\Delta GMV \le 0
\]

となった場合、追加allocationを停止し、investment thesisを再評価する。

### 2. Relative Market Position Deteriorates

対象categoryのGMV shareが継続的に低下し、市場全体の成長を下回る状態になった場合、allocation priorityを引き下げる。

### 3. Operational Quality Falls Below Market

以下が同時に成立した場合、そのsegmentをallocation eligibilityから除外する。

\[
LateRate_s > LateRate_{market}
\]

かつ、

\[
LowReviewRate_s > LowReviewRate_{market}
\]

これは今回watches_gifts × RJを除外したものと同じルールである。

### 4. Seller Concentration Becomes Material

Top-3 seller GMV shareが約40%を超え、allocation recommendationがseller concentration assumptionによって大きく変化する場合、allocationを縮小または再評価する。

### 5. Acquisition Engine Weakens Materially

market-wide active customersとGMVが持続的に減少し、repeat purchasingがその減少を補えない場合、market-level investment thesis自体を再評価する。

---

## Final Recommendation

**INVEST — selective segment allocation.**

市場全体への均等投資ではなく、需要成長とoperational qualityの双方が確認されたsegmentへ重点的に資源配分する。

現時点の最優先segmentは **health_beauty × SP**。

推奨allocationは以下を基準とする。

- health_beauty × SP: ~40%
- housewares × SP: ~25%
- watches_gifts × SP: ~20%
- health_beauty × MG: ~10–15%
- watches_gifts × RJ: 0%

このrecommendationはrelative resource allocationであり、financial return forecastではない。