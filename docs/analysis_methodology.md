# 分析方法論

## 1. 分析方針

投資分析で必要な指標は自然な粒度が異なるため、`order_base` と `item_base` の2つの分析基盤を分けています。

この設計の主目的は、1:N tableを無理に1つへ結合して発生する**重複集計（join explosion）**を避けることです。

---

## 2. Order Base

### 粒度

- 1 row = 1 order
- unique key = `order_id`

### 主な用途

- 月次orders
- active customers
- customer geography
- repeat / retention
- payment
- delivery
- review

### JOINルール

Order-levelの1:N tableはorder grainへ縮約してからJOINします。

- payments：`order_id`単位に集約
- reviews：各orderのlatest reviewを1件だけ採用

---

## 3. Item Base

### 粒度

- 1 row = 1 order item
- unique key = (`order_id`, `order_item_id`)

### 主な用途

- Merchandise GMV
- freight
- product
- category
- seller
- category × geography × time分析

1つのorderに複数product / category / sellerが含まれる可能性があるため、これらの属性はitem grainで保持します。

---

## 4. 指標集計ルール

各指標は自然なgrainで計算します。

- Merchandise GMV = `SUM(order_items.price)`
- Freight charged = `SUM(order_items.freight_value)`
- Orders = `COUNT(DISTINCT order_id)`
- Customers = `COUNT(DISTINCT customer_unique_id)`
- AOV = Merchandise GMV / GMV Orders
- Customer payment valueはorder-level指標として扱う
- Review / delivery指標はorder grainで評価する

比率指標はsubgroup比率の単純平均ではなく、**分子・分母を再集計して計算**します。

---

## 5. 分析対象期間

Primary analysis window：

```text
2017-02-01 <= order_purchase_timestamp < 2018-09-01
```

19か月、98,292 ordersを対象とします。

2016年後半は観測が疎で連続性が弱く、2018年9月以降もtrailing sparse periodのため除外しています。

このwindowは`00_data_audit.sql`で確定し、下流分析では再定義しません。

---

## 6. Customer Entity

JOINには`customer_id`を使用します。

Repeat / retentionの顧客entityには`customer_unique_id`を使用します。

```text
customer_unique_id (1) -> (N) customer_id
```

したがって、`customer_id`をrepeat customerの単位として扱いません。

---

## 7. Review Canonicalization

Reviewはorderあたり複数行存在する可能性があるため、latest reviewを採用します。

```sql
ORDER BY
    review_answer_timestamp DESC,
    review_creation_date DESC,
    review_id DESC
```

`ROW_NUMBER() = 1` をcanonical reviewとします。

複数reviewの単純平均は、顧客が実際には入力していない中間的なscoreを作るため採用しません。

---

## 8. Delivery / Review Eligibility

Anomaly rowを一律削除せず、KPIごとにeligibilityを定義します。

### Delivery time

必要timestampが存在し、時間順序が分析可能なorderのみを対象にします。

### Late delivery

`order_delivered_customer_date` と `order_estimated_delivery_date` が存在するorderを分母にします。

### Review

`review_score`が存在するorderを分母にします。

この方針により、1つの異常値を理由に他の正常な指標まで失うことを避けます。

---

## 9. Geography

Raw geolocationはZIP prefixがuniqueではないため、customer / sellerへ直接JOINしません。

カテゴリ・地域分析では、customers / sellers tableのstate / cityをcanonical categorical geographyとして利用します。

座標が必要な場合のみ、geolocationをZIP prefix単位に事前集約して利用します。

---

## 10. Comparable Period

Category / regionのgrowth comparisonはseasonalityを抑えるため、同一暦月で比較します。

```text
Prior:   2017-02-01 <= purchase < 2017-09-01
Current: 2018-02-01 <= purchase < 2018-09-01
```

Growth rateだけではlow-base effectが強いため、absolute GMV growthとcurrent scaleを併用します。

---

## 11. Allocation Logic

候補segmentは以下の順で評価します。

1. Positive absolute GMV growth
2. Delivery / reviewによるeligibility gate
3. `sqrt(Current GMV × Absolute GMV Growth)` によるopportunity score
4. Top-3 seller shareによるdiversification adjustment
5. Eligible segment間でrelative allocationへ正規化

Allocationはexpected return / ROI / IRRではなく、**Commercial DD上の相対的な資源配分優先度**です。

---

## 12. Uncertainty / Sensitivity

Seller concentration adjustmentを外した場合のallocationと比較し、ranking sensitivityを確認します。

`health_beauty × SP` が両仕様で1位を維持する一方、2位・3位は入れ替わるため、トップ候補は比較的頑健、下位配分は仮定に敏感と解釈します。

---

## 13. Financial DDとの境界

Olist公開データにはtake rate、margin、CAC、incremental investment等がないため、ROI / IRR / expected profitは識別できません。

したがって、本分析の最終判断はCommercial DD上のGOではなく、**Financial DD完了までWAIT**とします。
