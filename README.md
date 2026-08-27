# 投資デューデリジェンスと成長戦略

> Olist公開データを用いて、データ監査から市場・カテゴリ・地域分析、リスク評価、不確実性評価、資源配分、最終投資判断までを一貫して行ったCommercial Due Diligenceです。

## 最終判断

# WAIT — 財務ユニットエコノミクスの検証待ち

商業面・オペレーション面では選択的な投資を支持する結果が得られました。一方、公開データにはtake rate、margin、CAC、incremental investment、cash flowが含まれず、ROI / IRRを識別できません。

- **Commercial DD：GO**
- **Financial DD：未完了**
- **Final Decision：WAIT**

Financial DDを通過した場合の相対的な資源配分優先度は次のとおりです。

![推奨資源配分](figures/04_recommended_allocation.svg)

| Rank | Segment | Relative allocation |
|---:|---|---:|
| 1 | **health_beauty × SP** | **28.71%** |
| 2 | **bed_bath_table × SP** | **18.39%** |
| 3 | **sports_leisure × SP** | **18.20%** |
| 4 | **housewares × SP** | **18.13%** |
| 5 | **computers_accessories × SP** | **16.58%** |

> Allocationは期待収益率や最適資本配分ではありません。観測されたscale、absolute growth、market-share shift、operational quality、seller diversificationに基づく**相対優先度**です。

---

## ビジネス上の問い

> **このマーケットプレイスへ投資すべきか。投資候補が存在するなら、どのカテゴリ・地域を優先し、どの条件で投資仮説を撤回すべきか。**

分析フロー：

```text
Business Problem
→ Decision Criteria
→ Metric Tree
→ Data Audit
→ Diagnostic Analysis
→ Candidate Screening
→ Risk Screening
→ Allocation
→ Uncertainty / Robustness
→ Decision
```

目的はSQLやPythonの利用自体ではなく、**不完全な観測データから何を判断でき、何を判断できないかを切り分けること**です。

---

# 1. 市場全体

![月次GMV推移](figures/01_monthly_gmv.svg)

商品GMVは2017年に急拡大し、2018年には横ばい化する兆候があります。AOVに明確な上昇トレンドはなく、成長は主にactive customersとorder volumeによって説明されます。

90-day repeat rateも低く、market growthは新規顧客獲得への依存が大きいと解釈します。

したがって、2017年の高成長率を将来へ単純外挿せず、market-wide investmentではなくsegment selectionを行います。

---

# 2. Category / Region Opportunity

![カテゴリ機会分析](figures/02_category_opportunity.svg)

Comparable periodはseasonalityを抑えるため同一暦月を比較します。

```text
Prior:   2017-02-01 <= purchase < 2017-09-01
Current: 2018-02-01 <= purchase < 2018-09-01
```

## Candidate selectionを手入力から機械生成へ変更

旧版では候補category × stateをSQLへ直接記述していました。これは候補選択にanalyst discretionが残るため廃止しました。

現在は**全category × customer_state**に同一screenを適用します。

```text
both periods observed
→ current GMV >= 95th percentile
→ current orders >= 100
→ positive absolute GMV growth
→ positive GMV-share change
→ operational risk screen
→ candidate
```

95th percentileと100 ordersは推定された自然定数ではなく、意思決定上のscreening assumptionsです。そのため後段でthreshold sensitivityを確認します。

---

# 3. Operational Risk

![候補セグメントのリスク比較](figures/03_candidate_risk.svg)

遅配率と低評価率はorder grainで定義します。

$$
LateRate
=
\frac{LateOrders}{LateDeliveryEligibleOrders}
$$

$$
LowReviewRate
=
\frac{ReviewScore\le2}{ReviewEligibleOrders}
$$

Opportunity screen通過後、次の2条件が**同時に**market benchmarkより悪いsegmentを除外します。

$$
LateRate_s > LateRate_{market}
$$

かつ

$$
LowReviewRate_s > LowReviewRate_{market}
$$

代表例として`watches_gifts × RJ`は、成長機会は大きいものの両risk KPIがmarketより悪く、risk gateを通過しません。

---

# 4. 最有力segment

機械選定後も **health_beauty × SP** が1位です。

| Metric | Result |
|---|---:|
| 2018年2–8月 Merchandise GMV | **R$275,923** |
| Absolute GMV growth | **+R$205,740** |
| GMV growth | **+293%** |
| Late delivery rate | **7.10%** |
| Late delivery 95% CI | **[6.31%, 7.97%]** |
| Market late delivery rate | **8.17%** |
| Low-review rate | **10.34%** |
| Low-review 95% CI | **[9.41%, 11.36%]** |
| Market low-review rate | **14.62%** |
| Top-3 seller GMV share | **21.78%** |

Point estimateだけでなく、proportion KPIのsampling uncertaintyをWilson 95% confidence intervalで明示します。

---

# 5. Allocation Logic

Baseline scoreは説明可能性を優先したheuristicです。

$$
Score_s
=
GMV_s^{0.5}
\Delta GMV_s^{0.5}
(1-Concentration_s)^1
$$

ここで、

- `GMV` = current comparable-period merchandise GMV
- `ΔGMV` = prior comparable periodからのabsolute GMV growth
- `Concentration` = current-period Top-3 seller GMV share

です。

Eligible segmentをscore順に並べ、上位5segmentをportfolioとしてscore比率へ正規化します。

このモデルは構造的なreturn modelではないため、**平方根やseller penaltyの仕様そのものを検証対象**にします。

---

# 6. Statistical Uncertainty / Robustness

## 6.1 Wilson 95% Confidence Interval

Late delivery rateとLow review rateにはWilson intervalを使用します。

$$
CI_{Wilson}
=
\frac{
\hat p + z^2/(2n)
\pm
z\sqrt{\hat p(1-\hat p)/n + z^2/(4n^2)}
}{1+z^2/n}
$$

`z = 1.959964`です。

これにより、たとえば`health_beauty × SP`について「7.10% vs 8.17%」というpoint estimateだけでなく、推定幅まで示します。

## 6.2 Score specification robustness

Baseline scoreを一般化します。

$$
Score_s(\alpha,\beta,\gamma)
=
GMV_s^{\alpha}
\Delta GMV_s^{\beta}
(1-Concentration_s)^{\gamma}
$$

Grid:

```text
alpha ∈ {0.25, 0.50, 0.75, 1.00}
beta  ∈ {0.25, 0.50, 0.75, 1.00}
gamma ∈ {0.00, 0.50, 1.00, 1.50, 2.00}
```

計**80 specifications**を評価します。

ローカル再計算では、**health_beauty × SPは80/80 specificationsでrank 1**を維持しました。

したがって、トップ候補の結論は「平方根を使ったから」「Top-3 concentrationを線形で引いたから」という1つのmodel specificationだけには依存していません。

## 6.3 Candidate-screen sensitivity

Candidate selectionのthresholdも不確実性として扱います。

```text
Current GMV percentile ∈ {90, 92.5, 95, 97.5}
Minimum current orders ∈ {50, 100, 200}
```

12条件を評価し、`health_beauty × SP`がopportunity screenから脱落しないかを確認します。

---

# 7. なぜROI / IRRを出さないか

Olist公開データには以下がありません。

- take rate
- net revenue
- gross / contribution margin
- CAC
- marketing spend
- seller acquisition cost
- incremental investment requirement
- cash flow

さらに、投資によるincremental GMVの因果効果も識別できません。

したがってROI / IRR / expected profitを直接算出するとfalse precisionになります。

Commercial DDは**どのsegmentへ優先配分するか**を回答し、Financial DDは**その投資が必要リターンを満たすか**を検証する役割と分離します。

---

# 8. WAITからINVESTへ移行する条件

追加で以下を取得・検証します。

1. segment-level take rate
2. contribution margin
3. CAC
4. customer contribution LTV
5. seller acquisition economics
6. incremental marketing / operating investment
7. investment -> incremental GMVの期待効果

これらが投資ハードルを満たす場合に`INVEST`へ変更します。

---

# 9. 再評価・撤退トリガー

- comparable-period absolute GMV growth <= 0
- segment GMV shareの継続低下
- late deliveryとlow reviewがともにmarket benchmarkを上回る
- seller concentration悪化でrankingがspecification-sensitiveになる
- active customers / GMVが継続減少し、repeat purchasingで補えない

---

# 10. Reproducibility

実行順序：

```bash
python src/run_sql.py sql/00_data_audit.sql
python src/run_sql.py sql/01_analysis_base.sql
python src/run_sql.py sql/02_diagnostic_growth.sql
python src/run_sql.py sql/03_diagnostic_category.sql
python src/run_sql.py sql/04_diagnostic_region.sql
python src/run_sql.py sql/05_diagnostic_risk.sql
python src/run_sql.py sql/06_allocation.sql
python src/run_sql.py sql/07_uncertainty.sql
python src/make_figures.py
```

主な生成物：

```text
data/processed/order_base.parquet
data/processed/item_base.parquet
data/processed/opportunity_candidates.parquet
data/processed/candidate_risk.parquet
data/processed/allocation_recommendation.parquet
data/processed/risk_confidence_intervals.parquet
data/processed/specification_ranks.parquet
```

詳細な定義は `docs/analysis_methodology.md`、最終判断は `docs/investment_decision.md` を参照してください。
