# 投資判断メモ

## 最終判断

# WAIT — 財務ユニットエコノミクスの検証待ち

Commercial DDでは選択的な投資を支持する証拠が得られましたが、Olist公開データだけではROI / IRRを識別できません。

したがって、

- **Commercial DD：GO**
- **Financial DD：未完了**
- **Final Decision：WAIT**

とします。

Financial DDを通過した場合は、市場全体への均等配分ではなく、成長・顧客体験・seller diversificationが同時に確認されたsegmentへ重点配分します。

## Financial DD通過時の推奨相対配分

| 優先度 | Segment | Allocation |
|---|---|---:|
| コア | health_beauty × SP | ~40% |
| コア | housewares × SP | ~25% |
| 高成長・要監視 | watches_gifts × SP | ~20% |
| 拡張候補 | health_beauty × MG | ~10–15% |
| 除外 | watches_gifts × RJ | 0% |

この配分率はfinancial return forecastではなく、**observed marketplace evidenceに基づくrelative resource-allocation priority**です。

---

## 判断根拠

市場全体は2017年に急拡大した一方、2018年にはorders / active customers / GMVが横ばい化する兆候があります。

AOVには明確な上昇トレンドがなく、成長は主にcustomer acquisitionとorder volumeで説明されます。

また、returning customersは月次active customersの約2〜3%に留まり、完全な観測期間を持つcohortの90-day repeat rateは加重平均で約 **2.34%** でした。

したがって、marketplace全体としては新規顧客獲得への依存が大きいと判断します。

一方、成長はsegment間で均一ではありません。

最有力の **health_beauty × SP** は以下の特徴を持ちます。

- 2018年2–8月 商品GMV: R$275,923
- 同期間比較のabsolute GMV growth: +R$205,740
- GMV growth: +293%
- Late delivery rate: 7.10%
- Market late delivery rate: 8.17%
- Average review score: 4.28
- Low-review rate: 10.34%
- Market low-review rate: 14.62%
- Sellers: 303
- Top-3 seller GMV share: 21.78%

つまり、**scale + growth + customer experience + supply diversification** が同時に成立しています。

Seller concentration adjustmentの有無を比較しても、`health_beauty × SP` はallocation順位1位を維持します。

---

## Downside Risk

### 1. 新規顧客獲得依存

短期repeat purchasingが弱いため、新規顧客流入が鈍化するとorders / GMVも鈍化する可能性があります。

### 2. Seller集中

特に **watches_gifts × SP** は、

- Top-1 seller GMV share: 18.45%
- Top-3 seller GMV share: 44.66%

と集中度が高いです。

Seller concentration adjustmentを行うとallocationは、

- 調整なし: 28.79%
- 調整あり: 22.12%

まで低下します。

### 3. Operational Risk

**watches_gifts × RJ** は、

- Late delivery rate: 14.65%（market 8.17%）
- Low-review rate: 22.42%（market 14.62%）
- Average review score: 3.80
- Top-3 seller GMV share: 41.87%

となっており、GMV growthが高くても現時点ではallocation対象から除外します。

---

## ROI / IRRを算出しない理由

Olist公開データには以下が含まれていません。

- take rate
- net revenue
- gross / contribution margin
- CAC
- marketing spend
- seller acquisition cost
- incremental investment requirement
- cash flow

さらに、投資によるincremental GMVの因果効果も識別できません。

そのため、ROI / IRR / expected profitを直接推定するとfalse precisionになります。

Commercial DDは**どのsegmentへ優先配分するか**を回答し、Financial DDは**その投資が必要リターンを満たすか**を検証する役割と分けます。

---

## WAITからINVESTへ移行する条件

追加で以下を確認します。

1. segment-level take rate
2. contribution margin
3. CAC
4. customer contribution LTV
5. seller acquisition economics
6. incremental marketing / operating investment
7. investment -> incremental GMVの期待効果

これらが投資ハードルを満たす場合、最終判断を`WAIT`から`INVEST`へ変更します。

---

## 再評価・撤退トリガー

### 1. Growth Thesis Break

候補segmentのcomparable-period absolute GMV growthが0以下になった場合、追加allocationを停止します。

### 2. Relative Market Position Deterioration

対象categoryのGMV shareが継続的に低下し、市場全体の成長を下回る場合、allocation priorityを引き下げます。

### 3. Operational Quality Deterioration

以下が同時に成立した場合、そのsegmentをeligibilityから除外します。

$$
LateRate_s > LateRate_{market}
$$

かつ

$$
LowReviewRate_s > LowReviewRate_{market}
$$

### 4. Seller Concentration

Top-3 seller GMV shareが約40%を超え、allocation recommendationがconcentration assumptionに大きく依存する場合、配分を縮小または再評価します。

### 5. Acquisition Engine Weakening

Market-wide active customersとGMVが持続的に減少し、repeat purchasingがその減少を補えない場合、market-level thesis自体を再評価します。

---

## 結論

**現時点の最終判断はWAITです。**

ただしCommercial DD上の最優先segmentは **health_beauty × SP** であり、Financial DD通過時には約40%の相対配分を起点とします。

市場全体へ広く投資するのではなく、需要成長とoperational qualityが同時に確認できるsegmentへ選択的に資源配分する方針です。
