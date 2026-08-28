# 分析方法論

## 1. 分析方針

本分析では、`order_base`（1 row = 1 order）と `item_base`（1 row = 1 order item）を分離し、指標ごとに適切な集計粒度を維持します。1:Nのテーブルを無理に結合することで生じる行数の膨張を避け、注文単位のKPIと商品単位のGMVをそれぞれ別に集計します。

## 2. 分析期間

主要分析期間は以下のとおりです。

```text
2017-02-01 <= order_purchase_timestamp < 2018-09-01
```

カテゴリ・地域別の成長比較では、季節性の影響を抑えるため、前年と当年の同一暦月を比較します。

```text
Prior:   2017-02-01 <= purchase < 2017-09-01
Current: 2018-02-01 <= purchase < 2018-09-01
```

## 3. 指標定義

* Merchandise GMV = `SUM(order_items.price)`
* Orders = `COUNT(DISTINCT order_id)`
* Customers = `COUNT(DISTINCT customer_unique_id)`
* Late delivery rate = late orders / late-delivery-eligible orders
* Low review rate = review score <= 2 / review-eligible orders
* Seller concentration = current-period Top-3 seller GMV share

比率指標については、各部分集団の比率を単純平均するのではなく、分子と分母をそれぞれ再集計したうえで算出します。

## 4. 候補選定

旧版では、category × state の候補を手入力していました。この方法では分析者の裁量が残り、候補選定の再現性が弱いため廃止しました。

現在は、すべての `category × customer_state` を同一のルールで評価します。

### 機会選定基準

以下の条件をすべて満たすセグメントを候補とします。

1. Prior / Current の両期間にGMVが存在する
2. Current GMVが観測対象となる全セグメントの95パーセンタイル以上
3. Current orders >= 100
4. Absolute GMV growth > 0
5. GMV share change > 0

95パーセンタイルおよび100 ordersは、事前に明示した選定上の仮定です。これらの閾値に対する感応度は `sql/07_uncertainty.sql` で検証します。

### リスク除外基準

機会選定基準を通過したセグメントのうち、以下の2条件が**同時に**市場全体の基準値より悪いものを除外します。

```text
late_delivery_rate > market_late_delivery_rate
AND
low_review_rate > market_low_review_rate
```

この設計により、いずれか1つのKPIが市場平均を下回っただけで機械的に除外することを避けます。

## 5. 配分モデル

基準となるスコアは、説明可能性を優先したヒューリスティックな指標です。

```math
\mathrm{Score}_s =
\mathrm{GMV}_s^{0.5}
\Delta \mathrm{GMV}_s^{0.5}
(1-\mathrm{Concentration}_s)
```

ここで、

* `GMV` = 比較対象期間におけるCurrentのmerchandise GMV
* `ΔGMV` = PriorからCurrentへのGMVの絶対増加額
* `Concentration` = Top-3 seller GMV share

を表します。

最終ポートフォリオでは、リスク除外後に残ったセグメントのうち基準スコア上位5件を採用し、各セグメントのスコア比率に基づいて相対配分へ正規化します。

この配分値はexpected return、ROI、IRRを意味するものではありません。公開Olistデータにはtake rate、margin、CAC、追加投資額などの情報が含まれていないため、**Commercial DDにおける相対的な資源配分の優先度**として解釈します。

## 6. 標本不確実性

Late delivery rateとLow review rateには、Wilson 95% confidence intervalを付与します。

Wilson intervalは、通常のWald intervalと比べて、比率が0または1に近い場合やサンプルサイズが小さい場合でも安定しやすいため採用します。

```math
\mathrm{CI}_{\mathrm{Wilson}}
=
\frac{
\hat p + z^2/(2n)
\pm
z\sqrt{\hat p(1-\hat p)/n + z^2/(4n^2)}
}{
1+z^2/n
}
```

`z = 1.959964` を使用します。

## 7. モデル仕様の不確実性

基準スコアに用いる指数には任意性があるため、以下の一般形を用いて順位の安定性を評価します。

```math
\mathrm{Score}_s(\alpha,\beta,\gamma)
=
\mathrm{GMV}_s^{\alpha}
\Delta \mathrm{GMV}_s^{\beta}
(1-\mathrm{Concentration}_s)^{\gamma}
```

評価するパラメータの組合せは以下のとおりです。

```text
alpha ∈ {0.25, 0.50, 0.75, 1.00}
beta  ∈ {0.25, 0.50, 0.75, 1.00}
gamma ∈ {0.00, 0.50, 1.00, 1.50, 2.00}
```

合計80通りの仕様を評価し、各セグメントについて、1位となる割合、平均順位、最高順位、最低順位を算出します。

## 8. 選定基準の不確実性

機会選定基準で使用する閾値について、以下の組合せで感応度を確認します。

```text
Current GMV percentile ∈ {90, 92.5, 95, 97.5}
Minimum current orders ∈ {50, 100, 200}
```

GMVの絶対増加額が正であること、およびGMVシェアの変化が正であることは固定条件とします。

この検証により、最終候補が特定の1つの閾値設定にのみ依存して選ばれていないかを確認します。

## 9. 解釈上の境界

本分析は、マーケットプレイスの観察データを用いたCommercial DDです。

* セグメント間の魅力度比較は可能
* 資源配分の優先順位の比較は可能
* 投資によるincremental GMVの因果効果は識別できない
* ROI / IRR / expected profitは識別できない

したがって、最終的な投資判断はFinancial DDが完了するまで `WAIT` とします。
