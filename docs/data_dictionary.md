# データ辞書

本プロジェクトで使用するOlist公開データの主要テーブルと、分析上の役割・注意点を整理します。

## `olist_orders_dataset.csv`

**想定粒度:** 1行 = 1注文
**主キー:** `order_id`

| カラム                             | 用途                      |
| ------------------------------- | ----------------------- |
| `order_id`                      | 注文識別子。注文単位テーブルの結合キー     |
| `customer_id`                   | customersテーブルとの結合キー     |
| `order_status`                  | 注文状態                    |
| `order_purchase_timestamp`      | 購入日時。分析期間の抽出や月次推移の集計に使用 |
| `order_approved_at`             | 承認日時                    |
| `order_delivered_carrier_date`  | 配送業者への引渡日時              |
| `order_delivered_customer_date` | 顧客への配達日時                |
| `order_estimated_delivery_date` | 配達予定日時。遅延配送の判定に使用       |

分析対象期間は `2017-02-01 <= order_purchase_timestamp < 2018-09-01` とします。

---

## `olist_customers_dataset.csv`

**想定粒度:** 1行 = 1 `customer_id`
**主キー:** `customer_id`

| カラム                        | 用途                                 |
| -------------------------- | ---------------------------------- |
| `customer_id`              | ordersテーブルとの結合キー                   |
| `customer_unique_id`       | リピート・継続利用分析で使用する顧客識別子              |
| `customer_zip_code_prefix` | 郵便番号の先頭部分。raw geolocationには直接結合しない |
| `customer_city`            | 顧客の市区町村                            |
| `customer_state`           | 顧客の州。地域分析で使用                       |

`customer_unique_id (1) -> (N) customer_id` の関係があるため、リピート分析では `customer_unique_id` を使用します。

---

## `olist_order_items_dataset.csv`

**想定粒度:** 1行 = 1注文明細
**複合キー:** (`order_id`, `order_item_id`)

| カラム                   | 用途                         |
| --------------------- | -------------------------- |
| `order_id`            | ordersテーブルとの結合キー           |
| `order_item_id`       | 注文内の商品番号                   |
| `product_id`          | productsテーブルとの結合キー         |
| `seller_id`           | sellersテーブルとの結合キー          |
| `shipping_limit_date` | 発送期限                       |
| `price`               | 商品価格。Merchandise GMVの算出に使用 |
| `freight_value`       | 顧客に請求された送料                 |

Merchandise GMVは `SUM(price)` と定義します。

---

## `olist_products_dataset.csv`

**想定粒度:** 1行 = 1商品
**主キー:** `product_id`

| カラム                          | 用途                    |
| ---------------------------- | --------------------- |
| `product_id`                 | order_itemsテーブルとの結合キー |
| `product_category_name`      | ポルトガル語の商品カテゴリ名        |
| `product_name_lenght`        | 商品名の文字数               |
| `product_description_lenght` | 商品説明の文字数              |
| `product_photos_qty`         | 商品写真数                 |
| `product_weight_g`           | 重量                    |
| `product_length_cm`          | 長さ                    |
| `product_height_cm`          | 高さ                    |
| `product_width_cm`           | 幅                     |

カテゴリがNULLの場合は、分析上 `Unknown` として保持します。

---

## `product_category_name_translation.csv`

**想定粒度:** 1行 = 1カテゴリの翻訳対応

| カラム                             | 用途             |
| ------------------------------- | -------------- |
| `product_category_name`         | ポルトガル語の商品カテゴリ名 |
| `product_category_name_english` | 英語の商品カテゴリ名     |

対応する翻訳がない場合は `Untranslated` として保持します。

---

## `olist_sellers_dataset.csv`

**想定粒度:** 1行 = 1販売者
**主キー:** `seller_id`

| カラム                      | 用途                    |
| ------------------------ | --------------------- |
| `seller_id`              | order_itemsテーブルとの結合キー |
| `seller_zip_code_prefix` | 販売者の郵便番号先頭部分          |
| `seller_city`            | 販売者の市区町村              |
| `seller_state`           | 販売者の州                 |

販売者集中度の分析では、`order_items.seller_id` を注文明細単位で使用します。

---

## `olist_order_payments_dataset.csv`

**想定粒度:** 1行 = 1注文内の1支払レコード
**関係:** Orders -> Payments = 1:N

| カラム                    | 用途       |
| ---------------------- | -------- |
| `order_id`             | 注文識別子    |
| `payment_sequential`   | 注文内の支払連番 |
| `payment_type`         | 支払手段     |
| `payment_installments` | 分割回数     |
| `payment_value`        | 顧客支払額    |

`payment_value` は**売上高やGMVとは定義しません**。

注文単位の分析では、paymentsを `order_id` 単位に先に集約してから結合します。

---

## `olist_order_reviews_dataset.csv`

**関係:** Orders -> Reviews = 1:Nとなる可能性あり

| カラム                       | 用途       |
| ------------------------- | -------- |
| `review_id`               | レビュー識別子  |
| `order_id`                | 注文識別子    |
| `review_score`            | 1〜5の評価点  |
| `review_comment_title`    | レビュータイトル |
| `review_comment_message`  | レビュー本文   |
| `review_creation_date`    | レビュー作成日時 |
| `review_answer_timestamp` | レビュー回答日時 |

注文単位のKPIでは、最新レビューを代表レビューとして採用します。

---

## `olist_geolocation_dataset.csv`

**注意:** `geolocation_zip_code_prefix` は一意ではありません。

| カラム                           | 用途        |
| ----------------------------- | --------- |
| `geolocation_zip_code_prefix` | 郵便番号の先頭部分 |
| `geolocation_lat`             | 緯度        |
| `geolocation_lng`             | 経度        |
| `geolocation_city`            | 市区町村      |
| `geolocation_state`           | 州         |

未加工のgeolocationデータをcustomer / sellerへ直接結合すると行数が増幅するため、カテゴリ・地域分析では直接使用しません。

---

# 分析上の主要派生データ

## `data/processed/order_base.parquet`

**粒度:** 1行 = 1注文

主な用途：

* 月次注文数
* アクティブ顧客数
* リピート分析
* 支払分析
* 配送分析
* レビュー分析
* 顧客地域分析

主要な判定用フラグ：

* `delivery_time_eligible`
* `late_delivery_eligible`
* `review_eligible`

---

## `data/processed/item_base.parquet`

**粒度:** 1行 = 1注文明細

主な用途：

* Merchandise GMV
* カテゴリ分析
* 販売者分析
* 送料分析
* `category × customer_state × time` 単位の集計

---

## `data/processed/allocation_recommendation.parquet`

`sql/06_allocation.sql` で生成する最終的な資源配分推奨データです。

主なカラム：

* `category`
* `customer_state`
* `eligible_flag`
* `gmv_2018_feb_aug`
* `absolute_gmv_growth`
* `gmv_growth_pct`
* `late_delivery_rate_pct`
* `low_review_rate_pct`
* `seller_count`
* `top_3_sellers_gmv_share_pct`
* `adjusted_score`
* `allocation_pct`

`allocation_pct` は財務的リターンを表すものではなく、選定条件を満たしたセグメント間の**相対的な資源配分優先度**を表します。
