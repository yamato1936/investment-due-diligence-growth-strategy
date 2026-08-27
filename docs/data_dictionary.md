# データ辞書

本プロジェクトで使用するOlist公開データの主要tableと、分析上の役割・注意点を整理します。

## `olist_orders_dataset.csv`

**想定grain:** 1 row = 1 order  
**主キー:** `order_id`

| カラム | 用途 |
|---|---|
| `order_id` | order識別子。order-level tableのjoin key |
| `customer_id` | customers tableとのjoin key |
| `order_status` | order状態 |
| `order_purchase_timestamp` | 購入日時。analysis window / monthly trendに使用 |
| `order_approved_at` | 承認日時 |
| `order_delivered_carrier_date` | carrier引渡日時 |
| `order_delivered_customer_date` | 顧客配達日時 |
| `order_estimated_delivery_date` | 配達予定日時。late delivery判定に使用 |

分析対象期間は `2017-02-01 <= order_purchase_timestamp < 2018-09-01`。

---

## `olist_customers_dataset.csv`

**想定grain:** 1 row = 1 `customer_id`  
**主キー:** `customer_id`

| カラム | 用途 |
|---|---|
| `customer_id` | ordersとのjoin key |
| `customer_unique_id` | repeat / retentionで使用する顧客entity |
| `customer_zip_code_prefix` | ZIP prefix。raw geolocationへ直接joinしない |
| `customer_city` | 顧客city |
| `customer_state` | 顧客state。region分析で使用 |

`customer_unique_id (1) -> (N) customer_id` の関係があるため、repeat分析では`customer_unique_id`を使用します。

---

## `olist_order_items_dataset.csv`

**想定grain:** 1 row = 1 order item  
**複合キー:** (`order_id`, `order_item_id`)

| カラム | 用途 |
|---|---|
| `order_id` | ordersとのjoin key |
| `order_item_id` | order内item番号 |
| `product_id` | productsとのjoin key |
| `seller_id` | sellersとのjoin key |
| `shipping_limit_date` | shipping deadline |
| `price` | 商品価格。Merchandise GMVに使用 |
| `freight_value` | 顧客に請求されたfreight |

Merchandise GMVは `SUM(price)` と定義します。

---

## `olist_products_dataset.csv`

**想定grain:** 1 row = 1 product  
**主キー:** `product_id`

| カラム | 用途 |
|---|---|
| `product_id` | order_itemsとのjoin key |
| `product_category_name` | Portuguese category name |
| `product_name_lenght` | 商品名文字数 |
| `product_description_lenght` | 商品説明文字数 |
| `product_photos_qty` | 写真数 |
| `product_weight_g` | 重量 |
| `product_length_cm` | 長さ |
| `product_height_cm` | 高さ |
| `product_width_cm` | 幅 |

CategoryがNULLの場合は分析上`Unknown`として保持します。

---

## `product_category_name_translation.csv`

**想定grain:** 1 row = 1 category translation

| カラム | 用途 |
|---|---|
| `product_category_name` | Portuguese category |
| `product_category_name_english` | English category |

Translationがない場合は`Untranslated`として保持します。

---

## `olist_sellers_dataset.csv`

**想定grain:** 1 row = 1 seller  
**主キー:** `seller_id`

| カラム | 用途 |
|---|---|
| `seller_id` | order_itemsとのjoin key |
| `seller_zip_code_prefix` | seller ZIP prefix |
| `seller_city` | seller city |
| `seller_state` | seller state |

Seller concentration分析では`order_items.seller_id`をitem grainで使用します。

---

## `olist_order_payments_dataset.csv`

**想定grain:** 1 row = 1 payment sequence / order  
**関係:** Orders -> Payments = 1:N

| カラム | 用途 |
|---|---|
| `order_id` | order key |
| `payment_sequential` | payment sequence |
| `payment_type` | 支払手段 |
| `payment_installments` | 分割回数 |
| `payment_value` | 顧客支払額 |

`payment_value`は**revenueやGMVとは呼びません**。

Order-level分析では、paymentsを`order_id`単位へ先に集約してからJOINします。

---

## `olist_order_reviews_dataset.csv`

**関係:** Orders -> Reviews = 1:Nの可能性あり

| カラム | 用途 |
|---|---|
| `review_id` | review識別子 |
| `order_id` | order key |
| `review_score` | 1〜5のscore |
| `review_comment_title` | title |
| `review_comment_message` | comment |
| `review_creation_date` | review作成日時 |
| `review_answer_timestamp` | review回答日時 |

Order-level KPIではlatest reviewをcanonical reviewとして採用します。

---

## `olist_geolocation_dataset.csv`

**注意:** `geolocation_zip_code_prefix`はuniqueではありません。

| カラム | 用途 |
|---|---|
| `geolocation_zip_code_prefix` | ZIP prefix |
| `geolocation_lat` | latitude |
| `geolocation_lng` | longitude |
| `geolocation_city` | city |
| `geolocation_state` | state |

Raw geolocationをcustomer / sellerへ直接JOINするとrow multiplicationが発生するため、カテゴリ・地域分析では直接使用しません。

---

# 分析上の主要派生データ

## `data/processed/order_base.parquet`

**grain:** 1 row = 1 order

主な用途：

- monthly orders
- active customers
- repeat
- payment
- delivery
- review
- customer geography

主要eligibility：

- `delivery_time_eligible`
- `late_delivery_eligible`
- `review_eligible`

---

## `data/processed/item_base.parquet`

**grain:** 1 row = 1 order item

主な用途：

- Merchandise GMV
- category
- seller
- freight
- category × customer_state × time

---

## `data/processed/allocation_recommendation.parquet`

`sql/06_allocation.sql`で生成する最終allocation出力です。

主なカラム：

- `category`
- `customer_state`
- `eligible_flag`
- `gmv_2018_feb_aug`
- `absolute_gmv_growth`
- `gmv_growth_pct`
- `late_delivery_rate_pct`
- `low_review_rate_pct`
- `seller_count`
- `top_3_sellers_gmv_share_pct`
- `adjusted_score`
- `allocation_pct`

`allocation_pct`はfinancial returnではなく、eligible segment間の**相対的な資源配分優先度**です。
