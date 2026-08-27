# 投資判断メモ

## 最終判断

# WAIT — 財務ユニットエコノミクスの検証待ち

Commercial DDでは選択的な投資を支持する証拠が得られました。一方、Olist公開データにはtake rate、margin、CAC、incremental investment、cash flowがなく、ROI / IRRを識別できません。

したがって、

- **Commercial DD：GO**
- **Financial DD：未完了**
- **Final Decision：WAIT**

とします。

## Financial DD通過時の推奨相対配分

候補は手入力せず、全category × stateへ機械的なopportunity screenとrisk screenを適用し、baseline score上位5を採用します。

| 優先度 | Segment | Relative allocation |
|---|---|---:|
| 1 | **health_beauty × SP** | **28.71%** |
| 2 | **bed_bath_table × SP** | **18.39%** |
| 3 | **sports_leisure × SP** | **18.20%** |
| 4 | **housewares × SP** | **18.13%** |
| 5 | **computers_accessories × SP** | **16.58%** |

この配分はfinancial return forecastではなく、observed marketplace evidenceに基づくrelative resource-allocation priorityです。

## 最有力segment

`health_beauty × SP` は引き続き1位です。

- Current GMV: **R$275,923**
- Absolute GMV growth: **+R$205,740**
- GMV growth: **+293%**
- Late delivery rate: **7.10%**
- Late delivery Wilson 95% CI: **[6.31%, 7.97%]**
- Market late delivery rate: **8.17%**
- Low-review rate: **10.34%**
- Low-review Wilson 95% CI: **[9.41%, 11.36%]**
- Market low-review rate: **14.62%**
- Top-3 seller GMV share: **21.78%**

Point estimateだけでなく、比率KPIのsampling uncertaintyも明示します。

## Model specification robustness

Baseline scoreは、

$$
Score_s
=
GMV_s^{0.5}\Delta GMV_s^{0.5}(1-Concentration_s)
$$

というheuristicです。

この任意性を検証するため、

$$
Score_s(\alpha,\beta,\gamma)
=
GMV_s^{\alpha}\Delta GMV_s^{\beta}(1-Concentration_s)^{\gamma}
$$

として、

```text
alpha ∈ {0.25, 0.50, 0.75, 1.00}
beta  ∈ {0.25, 0.50, 0.75, 1.00}
gamma ∈ {0.00, 0.50, 1.00, 1.50, 2.00}
```

の**80 specifications**を評価します。

ローカル再計算では、`health_beauty × SP` は**80/80 specificationsでrank 1**を維持しました。したがってトップ候補の結論は、平方根やseller concentration penaltyの特定仕様だけには依存していません。

## Candidate selection robustness

旧版では候補5segmentをSQLへ直接記述していました。これは再現性の弱点だったため廃止しました。

現在は全category × stateから、

1. 両比較期間で観測
2. current GMV >= 95th percentile
3. current orders >= 100
4. positive absolute GMV growth
5. positive market-share change
6. operational risk gate

の順に候補を生成します。

さらにGMV percentileを90〜97.5、minimum ordersを50〜200で変える12条件を確認し、`health_beauty × SP` がopportunity screenから脱落しないことを確認します。

## Downside Risk

### 1. 新規顧客獲得依存

90-day repeatが低く、market growthは新規顧客流入への依存が大きい状態です。Acquisition engineが弱まればGMV growthも鈍化する可能性があります。

### 2. Seller concentration

Top-3 seller shareをscoreに含めていますが、penalty強度は構造推定値ではありません。そのためgammaを0〜2まで振ってrank stabilityを検証します。

### 3. Operational quality

Opportunity screenを通っても、late deliveryとlow reviewの両方がmarketより悪いsegmentは除外します。代表例として`watches_gifts × RJ` は旧分析同様、risk gateを通過しません。

### 4. Screening assumptions

95th-percentile GMV thresholdと100-order thresholdは意思決定上のscreening assumptionsです。データ生成過程から推定された自然定数ではないため、sensitivity analysis対象とします。

## ROI / IRRを算出しない理由

公開データには以下がありません。

- take rate
- net revenue
- gross / contribution margin
- CAC
- marketing spend
- seller acquisition cost
- incremental investment requirement
- cash flow

さらに、投資によるincremental GMVの因果効果も識別できません。

したがって、Commercial DDは**どのsegmentを優先するか**を回答し、Financial DDは**その投資が必要リターンを満たすか**を検証する役割と分離します。

## WAITからINVESTへ移行する条件

1. segment-level take rate
2. contribution margin
3. CAC
4. customer contribution LTV
5. seller acquisition economics
6. incremental marketing / operating investment
7. investment -> incremental GMVの期待効果

これらを取得し、投資ハードルを満たすことを確認した場合に`INVEST`へ変更します。

## 再評価・撤退トリガー

- comparable-period absolute GMV growth <= 0
- GMV shareの継続低下
- late deliveryとlow reviewがともにmarket benchmarkを上回る
- seller concentration悪化によりrankが仕様依存になる
- active customers / GMVの継続減少をrepeat purchasingで補えない

## 結論

最終判断は**WAIT**です。

ただしCommercial DD上では、機械的な候補生成・比率KPIのconfidence interval・80通りのscore specificationを導入しても、**health_beauty × SPが最優先segment**という結論は維持されます。
