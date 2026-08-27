# 投資デューデリジェンスと成長戦略

> Olist公開データを用いて、データ監査から市場・カテゴリ・地域分析、リスク評価、資源配分、最終投資判断までを一貫して行った投資デューデリジェンス分析です。

## 最終判断

# WAIT — 財務ユニットエコノミクスの検証待ち

商業面・オペレーション面では**選択的な投資を支持する結果**が得られました。一方、公開データには take rate、粗利、CAC、追加投資額など、投資リターンを検証するために必要な財務情報が含まれていません。

したがって、本分析の結論は以下です。

- **Commercial DD：GO** — 魅力的なカテゴリ × 地域の投資候補を特定
- **Financial DD：未完了** — ROI / IRR を識別するためのデータが不足
- **最終判断：WAIT** — 財務ユニットエコノミクスの確認後に投資実行を判断

Financial DDを通過した場合の**相対的な資源配分優先度**は以下です。

![推奨資源配分](figures/04_recommended_allocation.svg)

| 優先度 | セグメント | 相対配分 |
|---|---|---:|
| コア | **health_beauty × SP** | **40.78%** |
| コア | **housewares × SP** | **25.75%** |
| 高成長・要監視 | **watches_gifts × SP** | **22.12%** |
| 拡張候補 | **health_beauty × MG** | **11.35%** |
| 除外 | watches_gifts × RJ | **0%** |

> この配分率は期待収益率や最適資本配分ではありません。観測された需要成長、オペレーション品質、seller分散度に基づく**相対的な資源配分優先度**です。

---

## ビジネス上の問い

> **このマーケットプレイスへ投資すべきか。投資候補が存在するなら、どのカテゴリ・地域を優先し、どの条件で投資仮説を撤回すべきか。**

分析は次の順で設計しました。

```text
Business Problem
→ Decision Criteria
→ Metric Tree
→ Data Audit
→ Diagnostic Analysis
→ Hypothesis
→ Validation
→ Risk Screening
→ Allocation
→ Uncertainty
→ Decision
```

目的はSQLやPythonそのものを見せることではなく、**不完全な取引データから、どこまで意思決定でき、どこから先は追加データが必要かを切り分けること**です。

---

# 主な分析結果

## 1. マーケットプレイスGMVは2017年に拡大し、2018年に横ばいへ

![月次GMV推移](figures/01_monthly_gmv.svg)

商品GMVは2017年2月の約 **R$0.25M** から急拡大し、2018年の多くの月では約 **R$0.85M〜R$1.0M** のレンジで推移しました。

一方、2018年には2017年のような加速的な成長は継続していません。AOVにも明確な上昇トレンドがなく、過去の成長は主に**active customersと注文数の増加**によって説明されます。

### 投資上の含意

2017年の成長率を将来へそのまま外挿するのは危険です。マーケット全体へ均等に資源配分するより、成長の質が高いセグメントを選別する必要があります。

---

## 2. 顧客成長の質は弱く、新規獲得依存が大きい

月次ordersとactive customersはほぼ1対1で増減しており、1 active customerあたりのordersは概ね **1.0** 付近です。

2018年時点でもreturning customersは月次active customersの約 **2〜3%** にとどまり、完全な90日観測期間を持つcohortの加重平均90-day repeat rateは約 **2.34%** でした。

$$
Repeat_{90d}
=
\frac{\text{90日以内に2回目の購入を行った顧客数}}
{\text{90日間を完全に観測できる顧客数}}
$$

### 投資上の含意

新規顧客獲得が鈍化した場合、短期repeatだけではこれまでのGMV成長を補えない可能性があります。

### 制約

ここでの「初回購入」はdataset上の**first observed purchase**です。観測開始前の購買履歴はないため、顧客の真の生涯初回購入とは限りません。

---

## 3. 成長機会はカテゴリ間で大きく異なる

![カテゴリ機会分析](figures/02_category_opportunity.svg)

カテゴリ評価では、成長率だけでなく以下を組み合わせました。

- 現在のGMV規模
- 同一暦月で比較したGMV成長率
- 絶対GMV成長額
- 市場シェアの変化

比較期間はseasonalityの影響を抑えるため、同一暦月に揃えています。

```text
Prior:   2017-02-01 <= purchase < 2017-09-01
Current: 2018-02-01 <= purchase < 2018-09-01
```

市場全体の同期間GMV成長率は約 **115%** です。

大規模カテゴリのうち、`health_beauty`、`watches_gifts`、`housewares` などが有力候補になりました。一方、`construction_tools_construction` は約3,000%超の高成長ですがprior-periodの規模が小さいため、**低ベースの外れ値**として扱っています。

### 投資上の含意

高い成長率だけで候補を決めず、**規模 × 絶対成長 × 相対成長**を同時に見る必要があります。

---

# 地域別の機会

有力カテゴリをcustomer_state別に分解すると、São Paulo（`SP`）が最大市場で、Minas Gerais（`MG`）などに選択的な拡張余地が確認できました。

最有力セグメントは **health_beauty × SP** です。

| 指標 | 結果 |
|---|---:|
| 2018年2–8月 商品GMV | **R$275,923** |
| 同期間比較の絶対GMV成長額 | **+R$205,740** |
| GMV成長率 | **+293%** |
| 遅配率 | **7.10%** |
| 市場遅配率 | **8.17%** |
| 平均レビュー | **4.28** |
| 低評価率（2以下） | **10.34%** |
| 市場低評価率 | **14.62%** |
| seller数 | **303** |
| Top-3 seller GMV share | **21.78%** |

このセグメントでは、**規模・成長・顧客体験・seller分散**の4条件が同時に成立しています。

---

# オペレーショナルリスク

高成長であっても、delivery / reviewの品質が悪ければ配分対象から除外します。

![候補セグメントのリスク比較](figures/03_candidate_risk.svg)

市場ベンチマークは以下です。

$$
LateRate
=
\frac{\text{遅配注文数}}
{\text{遅配判定可能な注文数}}
$$

市場遅配率：**8.17%**

$$
LowReviewRate
=
\frac{\text{review scoreが2以下の注文数}}
{\text{review判定可能な注文数}}
$$

市場低評価率：**14.62%**

大半の候補は両指標で市場平均を上回る品質を示しましたが、`watches_gifts × RJ` は明確な例外でした。

| 指標 | watches_gifts × RJ | 市場 |
|---|---:|---:|
| 遅配率 | **14.65%** | 8.17% |
| 低評価率 | **22.42%** | 14.62% |
| 平均レビュー | **3.80** | — |

そのため、GMV成長が強くても現時点ではallocation対象から除外しています。

---

# Seller集中リスク

成長セグメントでも、GMVが少数sellerに依存している場合は供給側の脆弱性があります。

| セグメント | seller数 | Top-3 seller GMV share |
|---|---:|---:|
| health_beauty × SP | 303 | **21.78%** |
| housewares × SP | 275 | **11.93%** |
| health_beauty × MG | 155 | **35.07%** |
| watches_gifts × SP | 55 | **44.66%** |
| watches_gifts × RJ | 42 | **41.87%** |

`watches_gifts × SP` は需要面では魅力的ですが、Top-3 seller shareが **44.66%** と高く、最終配分では減点しています。

---

# 配分ロジック

配分モデルは、説明可能性を優先してシンプルなルールで設計しています。

## Step 1 — Eligibility Gate

絶対GMV成長額が正であることを前提とし、以下の2つが**同時に**市場より悪い場合は除外します。

$$
LateRate_s > LateRate_{market}
$$

かつ

$$
LowReviewRate_s > LowReviewRate_{market}
$$

このルールにより `watches_gifts × RJ` を除外しました。

## Step 2 — Opportunity Score

$$
BaseScore_s
=
\sqrt{GMV^{current}_s \times \Delta GMV_s}
$$

ここで、`GMV current` は2018年2–8月の商品GMV、`ΔGMV` は2017年同期間からの絶対GMV成長額です。

成長率ではなく絶対成長額を使うことで、低ベース効果を抑えています。

## Step 3 — Seller Concentration Adjustment

$$
Diversification_s
=
1 - Top3SellerShare_s
$$

$$
AdjustedScore_s
=
BaseScore_s \times Diversification_s
$$

## Step 4 — Relative Allocation

$$
Allocation_s
=
\frac{AdjustedScore_s}
{\sum_j AdjustedScore_j}
$$

最終結果は次のとおりです。

| セグメント | 配分 |
|---|---:|
| health_beauty × SP | **40.78%** |
| housewares × SP | **25.75%** |
| watches_gifts × SP | **22.12%** |
| health_beauty × MG | **11.35%** |
| watches_gifts × RJ | **0%** |

---

# 感度分析

seller concentration adjustmentを外して順位の安定性を確認しました。

| セグメント | 集中度調整なし | 集中度調整あり |
|---|---:|---:|
| health_beauty × SP | 37.55% | **40.78%** |
| housewares × SP | 21.06% | **25.75%** |
| watches_gifts × SP | 28.79% | **22.12%** |
| health_beauty × MG | 12.59% | **11.35%** |

`health_beauty × SP` はどちらの仕様でも1位を維持しています。一方、`housewares × SP` と `watches_gifts × SP` の順位は集中度の扱いに影響されます。

したがって、約40%というトップ推奨は比較的頑健ですが、2位・3位の厳密な割合は**仮定に対して感度がある**と解釈します。

---

# ROI / IRRを算出しない理由

投資ROIを評価するには、少なくとも投資によって生じる**増分利益**と**投資額**が必要です。

$$
ROI
=
\frac{Incremental\ Profit - Investment}
{Investment}
$$

Olist公開データでは以下が観測できません。

- marketplace take rate
- net revenue
- gross / contribution margin
- CAC
- marketing spend
- seller acquisition cost
- fulfillment / servicing cost
- incremental investment requirement
- cash flow

また、次の因果関係も識別できません。

$$
Investment \rightarrow Incremental\ GMV
$$

したがって、

$$
GMV\ Growth \neq ROI
$$

です。GMV成長をROIへ読み替えると、根拠のない精度を作ることになります。

---

# WAITからINVESTへ移行する条件

Commercial DDでは投資候補を特定できています。残る論点はFinancial DDです。

投資承認前に、少なくとも以下を追加検証する必要があります。

1. セグメント別take rate
2. contribution margin
3. CAC
4. customer contribution LTV
5. seller acquisition economics
6. incremental marketing / operating investment
7. 投資によるincremental GMVの期待値

これらによりunit economicsと投資ハードルレートを満たすことを確認できれば、`WAIT` から `INVEST` へ移行します。

---

# 主なDownside Risk

- **新規顧客獲得依存**：repeatが弱く、acquisition slowdownがGMVへ直結する可能性
- **市場成長の鈍化**：2018年にmarket-wide growthが横ばい化
- **seller集中**：特に `watches_gifts × SP` はTop-3 shareが44.66%
- **オペレーション品質**：`watches_gifts × RJ` の遅配・低評価が市場を大幅に下回る
- **財務可視性の不足**：commercial attractivenessとfinancial returnは別物

---

# 撤退・再評価トリガー

1. **成長仮説の崩れ**：候補segmentの同期間比較absolute GMV growthが0以下
2. **相対ポジション悪化**：対象categoryが市場平均を継続的に下回り、GMV shareも低下
3. **品質悪化**：遅配率と低評価率が同時に市場平均を上回る
4. **seller集中の上昇**：Top-3 shareが約40%を超え、配分結果が集中度仮定に大きく依存
5. **acquisition engineの弱体化**：active customersとGMVが持続的に減少し、repeatで補えない

---

# データと分析設計

## 使用データ

Brazilian E-Commerce Public Dataset by Olistの主要9テーブルを使用しています。

- `orders`
- `customers`
- `order_items`
- `products`
- `product_category_name_translation`
- `sellers`
- `order_payments`
- `order_reviews`
- `geolocation`

## 分析対象期間

```text
2017-02-01 <= order_purchase_timestamp < 2018-09-01
```

**19か月、98,292 orders** をprimary analysis windowとしています。

## 主要指標

商品GMV：

$$
Merchandise\ GMV = \sum order\_items.price
$$

AOV：

$$
AOV = \frac{Merchandise\ GMV}{GMV\ Orders}
$$

`payment_value` は顧客支払額として扱い、GMVやrevenueとは呼びません。

## 分析粒度

`order_base`：1 row = 1 order。orders、customers、repeat、payment、delivery、reviewに使用。

`item_base`：1 row = 1 order item。GMV、category、seller、freight、category × geographyに使用。

この分離により、1:N table同士のJOINによる重複集計を防いでいます。

詳細は以下を参照してください。

- [分析方法論](docs/analysis_methodology.md)
- [データ辞書](docs/data_dictionary.md)
- [投資判断メモ](docs/investment_decision.md)

---

# リポジトリ構成

```text
.
├── README.md
├── docs/
│   ├── analysis_methodology.md
│   ├── data_dictionary.md
│   └── investment_decision.md
├── figures/
│   ├── 01_monthly_gmv.svg
│   ├── 02_category_opportunity.svg
│   ├── 03_candidate_risk.svg
│   └── 04_recommended_allocation.svg
├── sql/
│   ├── 00_data_audit.sql
│   ├── 01_analysis_base.sql
│   ├── 02_diagnostic_growth.sql
│   ├── 03_diagnostic_category.sql
│   ├── 04_diagnostic_region.sql
│   ├── 05_diagnostic_risk.sql
│   └── 06_allocation.sql
├── src/
│   ├── run_sql.py
│   └── make_figures.py
├── data/
│   ├── raw/        # ローカルのみ
│   └── processed/  # ローカル生成物
├── requirements.txt
└── pyproject.toml
```

---

# 再現手順

## 1. Clone

```bash
git clone https://github.com/yamato1936/investment-due-diligence-growth-strategy.git
cd investment-due-diligence-growth-strategy
```

## 2. Python環境を作成

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 3. Olist CSVを `data/raw/` に配置

```text
data/raw/
├── olist_customers_dataset.csv
├── olist_geolocation_dataset.csv
├── olist_order_items_dataset.csv
├── olist_order_payments_dataset.csv
├── olist_order_reviews_dataset.csv
├── olist_orders_dataset.csv
├── olist_products_dataset.csv
├── olist_sellers_dataset.csv
└── product_category_name_translation.csv
```

## 4. Data Audit

```bash
python src/run_sql.py sql/00_data_audit.sql
```

## 5. Analytical Baseを生成

```bash
python src/run_sql.py sql/01_analysis_base.sql
```

生成物：

```text
data/processed/order_base.parquet
data/processed/item_base.parquet
```

## 6. Diagnostic Analysis

```bash
python src/run_sql.py sql/02_diagnostic_growth.sql
python src/run_sql.py sql/03_diagnostic_category.sql
python src/run_sql.py sql/04_diagnostic_region.sql
python src/run_sql.py sql/05_diagnostic_risk.sql
```

## 7. Allocationを生成

```bash
python src/run_sql.py sql/06_allocation.sql
```

生成物：

```text
data/processed/allocation_recommendation.parquet
```

## 8. Figureを生成

```bash
python src/make_figures.py
```

---

# 最終提言

## WAIT — 財務ユニットエコノミクスの検証待ち

市場全体への一律投資は推奨しません。

一方、Commercial DDでは **health_beauty × SP** を最優先とする明確な投資候補を特定できています。Financial DDでunit economicsが投資基準を満たすことを確認できた場合、初期の資源配分は以下を目安とします。

1. **health_beauty × SP — 約40%**
2. **housewares × SP — 約25%**
3. **watches_gifts × SP — 約20%**（seller集中を継続監視）
4. **health_beauty × MG — 約10〜15%**
5. **watches_gifts × RJ — 0%**

本分析は**どこへ投資すべきか**を示しています。残るFinancial DDで、**そもそも期待リターンが投資実行に値するか**を検証する必要があります。
