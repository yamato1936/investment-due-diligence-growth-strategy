# 分析方法論

## 1. 分析方針

本分析は、`order_base`（1 row = 1 order）と `item_base`（1 row = 1 order item）を分離し、指標ごとの自然な粒度を維持します。1:N tableを無理に結合して起きるjoin explosionを避け、order-level KPIとitem-level GMVを別々に集計します。

## 2. 分析期間

Primary analysis window:

```text
2017-02-01 <= order_purchase_timestamp < 2018-09-01
```

Category / region growth comparisonはseasonalityを抑えるため、同一暦月で比較します。

```text
Prior:   2017-02-01 <= purchase < 2017-09-01
Current: 2018-02-01 <= purchase < 2018-09-01
```

## 3. 指標定義

- Merchandise GMV = `SUM(order_items.price)`
- Orders = `COUNT(DISTINCT order_id)`
- Customers = `COUNT(DISTINCT customer_unique_id)`
- Late delivery rate = late orders / late-delivery-eligible orders
- Low review rate = review score <= 2 / review-eligible orders
- Seller concentration = current-period Top-3 seller GMV share

比率指標はsubgroup率の単純平均ではなく、分子・分母を再集計します。

## 4. Candidate selection

旧版ではcategory × stateの候補を手入力していました。これはanalyst discretionが残り、候補選定の再現性が弱いため廃止しました。

現在は全 `category × customer_state` を同一ルールで評価します。

### Opportunity screen

1. Prior / Currentの両期間にGMVが存在する
2. Current GMVが全observed segmentの95th percentile以上
3. Current orders >= 100
4. Absolute GMV growth > 0
5. GMV share change > 0

95th percentileと100 ordersは事前に明示したscreening assumptionsであり、`sql/07_uncertainty.sql` でthreshold sensitivityを確認します。

### Risk screen

Opportunity screen通過後、次の2条件が**同時に**market benchmarkより悪いsegmentを除外します。

```text
late_delivery_rate > market_late_delivery_rate
AND
low_review_rate > market_low_review_rate
```

この設計により、1つのKPIだけで自動的に除外しません。

## 5. Allocation model

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
- `ΔGMV` = prior periodからのabsolute GMV growth
- `Concentration` = Top-3 seller GMV share

です。

最終portfolioはrisk-eligible segmentのうちbaseline score上位5を採用し、そのscore比率でrelative allocationへ正規化します。

このallocationはexpected return / ROI / IRRではありません。公開Olistデータだけではtake rate、margin、CAC、incremental investmentがないため、**Commercial DD上の相対的な資源配分優先度**として解釈します。

## 6. Sampling uncertainty

Late delivery rateとLow review rateにはWilson 95% confidence intervalを付与します。

通常のWald intervalより、割合が境界に近い場合やsample sizeが小さい場合に安定するためです。

$$
CI_{Wilson}
=
\frac{
\hat p + z^2/(2n)
\pm
z\sqrt{\hat p(1-\hat p)/n + z^2/(4n^2)}
}{
1+z^2/n
}
$$

`z = 1.959964` を使用します。

## 7. Model specification uncertainty

Baseline scoreの指数が任意であることを明示し、以下の一般形でrank stabilityを評価します。

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

計80 specificationsを評価し、各segmentについてrank-1 share、average rank、best / worst rankを算出します。

## 8. Selection uncertainty

Opportunity screenの閾値について、次の組合せでsensitivityを確認します。

```text
Current GMV percentile ∈ {90, 92.5, 95, 97.5}
Minimum current orders ∈ {50, 100, 200}
```

Positive absolute growthとpositive market-share changeは固定します。

この検証により、最終候補が特定の1 thresholdだけで成立していないかを確認します。

## 9. 解釈上の境界

本分析はobservational marketplace dataを用いたCommercial DDです。

- Segment attractivenessの比較は可能
- Allocation priorityの比較は可能
- Investmentによるincremental GMVの因果効果は識別できない
- ROI / IRR / expected profitは識別できない

したがって、最終判断はFinancial DD完了まで`WAIT`とします。
