# Analysis Methodology

## Analytical Bases

Two analytical bases are used because the metrics required for the investment analysis exist at different natural grains.

### Order Base

Grain:

- 1 row = 1 order
- unique key = `order_id`

Primary use cases:

- monthly order growth
- active customers
- AOV
- customer geography
- repeat behavior
- payment behavior
- delivery performance
- review metrics

Order-level one-to-many tables are reduced before joining:

- payments are aggregated to order grain
- reviews are canonicalized to the latest review per order

### Item Base

Grain:

- 1 row = 1 order item
- unique key = (`order_id`, `order_item_id`)

Primary use cases:

- merchandise GMV
- product category
- product
- seller
- freight
- category × geography × time analysis

Product and seller attributes are retained at item grain because a single order may contain multiple products, categories, or sellers.

## Metric Aggregation Rules

Metrics are aggregated according to their natural grain.

- Merchandise GMV = `SUM(order_items.price)`
- Freight charged = `SUM(order_items.freight_value)`
- Orders = `COUNT(DISTINCT order_id)`
- Customers = `COUNT(DISTINCT customer_unique_id)`
- AOV = Merchandise GMV / Orders
- Customer payment value is an order-level metric and must not be summed from item-level duplicated rows.
- Review and delivery metrics are evaluated at order grain.

Ratio metrics are recomputed from their numerator and denominator rather than averaging subgroup ratios.

## Analysis Window

The primary analysis window is:

`2017-02-01 <= order_purchase_timestamp < 2018-09-01`

This window was established during the completed data audit and is not revalidated in downstream analysis.

## Data Quality Policy

Data anomalies are not globally removed.

Metric-specific eligibility rules are used where timestamps, reviews, or other fields are required for a particular KPI.