/*=============================================================================
 OLIST E-COMMERCE ANALYTICS — BUSINESS QUESTIONS & SQL ANSWERS
 Platform : Microsoft SQL Server
 Database : OlistDB
 Purpose  : Analytical queries to run AFTER loading the cleaned tables and
            setting up the relationships/schema. This file does not recreate
            tables or change any data.

 EXPECTED SQL TABLES (based on the SQL Server names used in the project):
   dbo.customers
   dbo.orders
   dbo.order_items
   dbo.order_payments
   dbo.order_reviews
   dbo.products
   dbo.sellers
   dbo.category_translation
   dbo.geolocation

 NOTE: The Power BI model uses longer names such as
       olist_orders_dataset. In SQL Server, previous project errors referenced
       dbo.orders, dbo.order_items, dbo.products and dbo.category_translation.
       If your actual table names differ, update the names in this script first.

 IMPORTANT ANALYTICAL RULE:
   order_items = one row per order line; order_payments = one row per payment
   sequence. Aggregate each fact table to order_id BEFORE joining both to
   orders, otherwise the joins can multiply rows and overstate sales/payments.

 The script uses SELECT statements only (plus USE/SET); it does not modify data.
=============================================================================*/

USE [OlistDB];
SET NOCOUNT ON;
GO

/*=============================================================================
 00 — PREFLIGHT: confirm the expected tables exist
=============================================================================*/
SELECT s.name AS schema_name, t.name AS table_name
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = N'dbo'
  AND t.name IN (N'customers', N'orders', N'order_items', N'order_payments',
                 N'order_reviews', N'products', N'sellers',
                 N'category_translation', N'geolocation')
ORDER BY t.name;
GO

/* 00B — Inspect table columns and data types. Compare these with your imports. */
SELECT TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'dbo'
  AND TABLE_NAME IN (N'customers', N'orders', N'order_items', N'order_payments',
                     N'order_reviews', N'products', N'sellers',
                     N'category_translation', N'geolocation')
ORDER BY TABLE_NAME, ORDINAL_POSITION;
GO

/*=============================================================================
 BUSINESS QUESTION 1
 What is the overall business performance (orders, customers, sales, freight,
 payments, average order value, and review score)?
=============================================================================*/
;WITH ItemByOrder AS
(
    SELECT order_id,
           SUM(COALESCE(price, 0)) AS item_sales,
           SUM(COALESCE(freight_value, 0)) AS freight_total,
           COUNT_BIG(*) AS order_lines
    FROM dbo.order_items
    GROUP BY order_id
),
PaymentByOrder AS
(
    SELECT order_id,
           SUM(COALESCE(payment_value, 0)) AS payment_total,
           COUNT_BIG(*) AS payment_records
    FROM dbo.order_payments
    GROUP BY order_id
),
CustomerMap AS
(
    SELECT customer_id,
           MAX(customer_unique_id) AS customer_unique_id
    FROM dbo.customers
    GROUP BY customer_id
),
ReviewByOrder AS
(
    SELECT order_id, AVG(CAST(review_score AS decimal(10,2))) AS avg_order_review_score
    FROM dbo.order_reviews
    GROUP BY order_id
),
OrderGrain AS
(
    SELECT o.order_id, cm.customer_unique_id,
           COALESCE(i.item_sales, 0) AS item_sales,
           COALESCE(i.freight_total, 0) AS freight_total,
           COALESCE(p.payment_total, 0) AS payment_total,
           r.avg_order_review_score
    FROM dbo.orders AS o
    LEFT JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
    LEFT JOIN ItemByOrder AS i ON i.order_id = o.order_id
    LEFT JOIN PaymentByOrder AS p ON p.order_id = o.order_id
    LEFT JOIN ReviewByOrder AS r ON r.order_id = o.order_id
)
SELECT COUNT_BIG(*) AS total_orders,
       COUNT(DISTINCT customer_unique_id) AS unique_customers,
       SUM(item_sales) AS total_item_sales,
       SUM(freight_total) AS total_freight,
       SUM(item_sales + freight_total) AS items_plus_freight,
       SUM(payment_total) AS total_payment_value,
       CAST(SUM(payment_total) / NULLIF(COUNT_BIG(*), 0) AS decimal(18,2)) AS avg_payment_per_order,
       CAST(AVG(avg_order_review_score) AS decimal(10,2)) AS avg_review_score_across_reviewed_orders
FROM OrderGrain;
GO

/*=============================================================================
 BUSINESS QUESTION 2
 How are orders, item sales, freight and payments trending by month?
 Use order purchase date as the primary order-date role.
=============================================================================*/
;WITH ItemByOrder AS
(
    SELECT order_id, SUM(COALESCE(price, 0)) AS item_sales,
           SUM(COALESCE(freight_value, 0)) AS freight_total
    FROM dbo.order_items GROUP BY order_id
),
PaymentByOrder AS
(
    SELECT order_id, SUM(COALESCE(payment_value, 0)) AS payment_total
    FROM dbo.order_payments GROUP BY order_id
),
Monthly AS
(
    SELECT DATEFROMPARTS(YEAR(o.order_purchase_timestamp), MONTH(o.order_purchase_timestamp), 1) AS order_month,
           COUNT_BIG(*) AS total_orders,
           SUM(COALESCE(i.item_sales, 0)) AS item_sales,
           SUM(COALESCE(i.freight_total, 0)) AS freight_total,
           SUM(COALESCE(p.payment_total, 0)) AS payment_total
    FROM dbo.orders AS o
    LEFT JOIN ItemByOrder AS i ON i.order_id = o.order_id
    LEFT JOIN PaymentByOrder AS p ON p.order_id = o.order_id
    WHERE o.order_purchase_timestamp IS NOT NULL
    GROUP BY DATEFROMPARTS(YEAR(o.order_purchase_timestamp), MONTH(o.order_purchase_timestamp), 1)
)
SELECT order_month, total_orders, item_sales, freight_total, payment_total,
       LAG(item_sales) OVER (ORDER BY order_month) AS prior_month_item_sales,
       CAST(100.0 * (item_sales - LAG(item_sales) OVER (ORDER BY order_month))
            / NULLIF(LAG(item_sales) OVER (ORDER BY order_month), 0) AS decimal(10,2)) AS mom_item_sales_growth_pct
FROM Monthly
ORDER BY order_month;
GO

/*=============================================================================
 BUSINESS QUESTION 3
 What is the order-status mix, and what share of orders is cancelled?
=============================================================================*/
SELECT order_status,
       COUNT_BIG(*) AS order_count,
       CAST(100.0 * COUNT_BIG(*) / NULLIF(SUM(COUNT_BIG(*)) OVER (), 0) AS decimal(10,2)) AS pct_of_orders
FROM dbo.orders
GROUP BY order_status
ORDER BY order_count DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 4
 Which product categories generate the most item sales?
=============================================================================*/
SELECT TOP (10)
       COALESCE(ct.product_category_name_english, p.product_category_name, N'(unknown)') AS product_category,
       SUM(COALESCE(oi.price, 0)) AS item_sales,
       SUM(COALESCE(oi.freight_value, 0)) AS freight_value,
       COUNT_BIG(*) AS order_lines,
       COUNT(DISTINCT oi.order_id) AS distinct_orders,
       SUM(COALESCE(oi.price, 0) + COALESCE(oi.freight_value, 0)) AS items_plus_freight
FROM dbo.order_items AS oi
JOIN dbo.products AS p ON p.product_id = oi.product_id
LEFT JOIN dbo.category_translation AS ct
       ON ct.product_category_name = p.product_category_name
GROUP BY COALESCE(ct.product_category_name_english, p.product_category_name, N'(unknown)')
ORDER BY item_sales DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 5
 Which customer states generate the most orders and unique customers?
=============================================================================*/
;WITH CustomerMap AS
(
    SELECT customer_id,
           MAX(customer_unique_id) AS customer_unique_id,
           MAX(customer_state) AS customer_state
    FROM dbo.customers
    GROUP BY customer_id
)
SELECT COALESCE(cm.customer_state, N'(unknown)') AS customer_state,
       COUNT(DISTINCT o.order_id) AS total_orders,
       COUNT(DISTINCT cm.customer_unique_id) AS unique_customers
FROM dbo.orders AS o
LEFT JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
GROUP BY COALESCE(cm.customer_state, N'(unknown)')
ORDER BY total_orders DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 6
 Which cities have the highest order volume?
=============================================================================*/
;WITH CustomerMap AS
(
    SELECT customer_id, MAX(customer_city) AS customer_city,
           MAX(customer_state) AS customer_state
    FROM dbo.customers GROUP BY customer_id
)
SELECT TOP (10) COALESCE(cm.customer_city, N'(unknown)') AS customer_city,
       COALESCE(cm.customer_state, N'') AS customer_state,
       COUNT(DISTINCT o.order_id) AS total_orders
FROM dbo.orders AS o
LEFT JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
GROUP BY COALESCE(cm.customer_city, N'(unknown)'), COALESCE(cm.customer_state, N'')
ORDER BY total_orders DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 7
 Which payment methods contribute most to payment value?
=============================================================================*/
SELECT payment_type,
       COUNT_BIG(*) AS payment_records,
       COUNT(DISTINCT order_id) AS orders_using_method,
       SUM(COALESCE(payment_value, 0)) AS payment_value,
       CAST(100.0 * SUM(COALESCE(payment_value, 0)) /
            NULLIF(SUM(SUM(COALESCE(payment_value, 0))) OVER (), 0) AS decimal(10,2)) AS pct_of_payment_value,
       CAST(AVG(CAST(payment_value AS decimal(18,2))) AS decimal(18,2)) AS avg_payment_record_value
FROM dbo.order_payments
GROUP BY payment_type
ORDER BY payment_value DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 8
 How do installment counts relate to payment value and order count?
=============================================================================*/
SELECT payment_installments,
       COUNT_BIG(*) AS payment_records,
       COUNT(DISTINCT order_id) AS distinct_orders,
       SUM(COALESCE(payment_value, 0)) AS total_payment_value,
       CAST(AVG(CAST(payment_value AS decimal(18,2))) AS decimal(18,2)) AS avg_payment_value
FROM dbo.order_payments
GROUP BY payment_installments
ORDER BY payment_installments;
GO

/*=============================================================================
 BUSINESS QUESTION 9
 What is the customer review-score distribution?
=============================================================================*/
SELECT review_score,
       COUNT_BIG(*) AS review_count,
       CAST(100.0 * COUNT_BIG(*) / NULLIF(SUM(COUNT_BIG(*)) OVER (), 0) AS decimal(10,2)) AS pct_of_reviews
FROM dbo.order_reviews
GROUP BY review_score
ORDER BY review_score DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 10
 What is the average review score by order status?
 Review scores are first aggregated to order grain to avoid order/review fan-out.
=============================================================================*/
;WITH ReviewByOrder AS
(
    SELECT order_id, AVG(CAST(review_score AS decimal(10,2))) AS avg_review_score,
           COUNT_BIG(*) AS review_records
    FROM dbo.order_reviews
    GROUP BY order_id
)
SELECT o.order_status,
       COUNT_BIG(*) AS orders_with_status,
       COUNT(r.avg_review_score) AS orders_with_reviews,
       CAST(AVG(r.avg_review_score) AS decimal(10,2)) AS avg_review_score,
       SUM(COALESCE(r.review_records, 0)) AS review_records
FROM dbo.orders AS o
LEFT JOIN ReviewByOrder AS r ON r.order_id = o.order_id
GROUP BY o.order_status
ORDER BY avg_review_score DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 11
 What is the overall delivery time and on-time delivery rate?
 Late = actual customer delivery date > estimated delivery date.
 Only orders with actual and estimated delivery dates are included in the rate.
=============================================================================*/
SELECT COUNT_BIG(*) AS delivered_orders_with_estimate,
       CAST(AVG(CAST(DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date) AS decimal(10,2))) AS decimal(10,2)) AS avg_days_purchase_to_delivery,
       CAST(AVG(CASE WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 1.0 ELSE 0.0 END) * 100 AS decimal(10,2)) AS on_time_delivery_rate_pct,
       SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_deliveries,
       CAST(AVG(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
                     THEN CAST(DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS decimal(10,2)) END) AS decimal(10,2)) AS avg_days_late_when_late
FROM dbo.orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;
GO

/*=============================================================================
 BUSINESS QUESTION 12
 Which states have the highest late-delivery rate?
=============================================================================*/
;WITH CustomerMap AS
(
    SELECT customer_id, MAX(customer_state) AS customer_state
    FROM dbo.customers GROUP BY customer_id
),
DeliveredOrders AS
(
    SELECT o.order_id, cm.customer_state,
           CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END AS is_late,
           DATEDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_customer_date) AS delivery_days,
           CASE WHEN o.order_delivered_customer_date IS NOT NULL
                     AND o.order_estimated_delivery_date IS NOT NULL THEN 1 ELSE 0 END AS has_comparable_dates
    FROM dbo.orders AS o
    LEFT JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
    WHERE o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT COALESCE(customer_state, N'(unknown)') AS customer_state,
       COUNT_BIG(*) AS delivered_orders,
       SUM(is_late) AS late_orders,
       CAST(100.0 * SUM(is_late) / NULLIF(COUNT_BIG(*), 0) AS decimal(10,2)) AS late_delivery_rate_pct,
       CAST(AVG(CAST(delivery_days AS decimal(10,2))) AS decimal(10,2)) AS avg_delivery_days
FROM DeliveredOrders
GROUP BY COALESCE(customer_state, N'(unknown)')
ORDER BY late_delivery_rate_pct DESC, delivered_orders DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 13
 At which step do delays occur: purchase-to-approval, approval-to-carrier,
 or carrier-to-customer? Shows average days and rows with valid dates per step.
=============================================================================*/
SELECT
    CAST(AVG(CASE WHEN order_purchase_timestamp IS NOT NULL AND order_approved_at IS NOT NULL
                  THEN CAST(DATEDIFF(HOUR, order_purchase_timestamp, order_approved_at) AS decimal(10,2)) / 24.0 END) AS decimal(10,2)) AS avg_days_purchase_to_approval,
    CAST(AVG(CASE WHEN order_approved_at IS NOT NULL AND order_delivered_carrier_date IS NOT NULL
                  THEN CAST(DATEDIFF(HOUR, order_approved_at, order_delivered_carrier_date) AS decimal(10,2)) / 24.0 END) AS decimal(10,2)) AS avg_days_approval_to_carrier,
    CAST(AVG(CASE WHEN order_delivered_carrier_date IS NOT NULL AND order_delivered_customer_date IS NOT NULL
                  THEN CAST(DATEDIFF(HOUR, order_delivered_carrier_date, order_delivered_customer_date) AS decimal(10,2)) / 24.0 END) AS decimal(10,2)) AS avg_days_carrier_to_customer,
    SUM(CASE WHEN order_approved_at < order_purchase_timestamp THEN 1 ELSE 0 END) AS invalid_approval_sequence_count,
    SUM(CASE WHEN order_delivered_carrier_date < order_approved_at THEN 1 ELSE 0 END) AS invalid_carrier_sequence_count,
    SUM(CASE WHEN order_delivered_customer_date < order_delivered_carrier_date THEN 1 ELSE 0 END) AS invalid_delivery_sequence_count
FROM dbo.orders;
GO

/*=============================================================================
 BUSINESS QUESTION 14
 Which sellers contribute most item sales and order volume?
=============================================================================*/
SELECT TOP (10)
       s.seller_id, s.seller_city, s.seller_state,
       COUNT_BIG(*) AS order_lines,
       COUNT(DISTINCT oi.order_id) AS distinct_orders,
       SUM(COALESCE(oi.price, 0)) AS item_sales,
       SUM(COALESCE(oi.freight_value, 0)) AS freight_value,
       CAST(AVG(CAST(oi.price AS decimal(18,2))) AS decimal(18,2)) AS avg_item_price
FROM dbo.order_items AS oi
JOIN dbo.sellers AS s ON s.seller_id = oi.seller_id
GROUP BY s.seller_id, s.seller_city, s.seller_state
ORDER BY item_sales DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 15
 Which products have the highest item sales?
 There is no product name in the supplied schema, so product_id is shown.
=============================================================================*/
SELECT TOP (20)
       p.product_id,
       COALESCE(ct.product_category_name_english, p.product_category_name, N'(unknown)') AS product_category,
       COUNT_BIG(*) AS order_lines,
       COUNT(DISTINCT oi.order_id) AS distinct_orders,
       SUM(COALESCE(oi.price, 0)) AS item_sales,
       SUM(COALESCE(oi.freight_value, 0)) AS freight_value
FROM dbo.order_items AS oi
JOIN dbo.products AS p ON p.product_id = oi.product_id
LEFT JOIN dbo.category_translation AS ct ON ct.product_category_name = p.product_category_name
GROUP BY p.product_id, COALESCE(ct.product_category_name_english, p.product_category_name, N'(unknown)')
ORDER BY item_sales DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 16
 Reconcile per-order item sales + freight against total payment value.
 This avoids joining raw item lines directly to raw payment records.
=============================================================================*/
;WITH ItemByOrder AS
(
    SELECT order_id,
           SUM(COALESCE(price, 0)) AS item_total,
           SUM(COALESCE(freight_value, 0)) AS freight_total
    FROM dbo.order_items GROUP BY order_id
),
PaymentByOrder AS
(
    SELECT order_id, SUM(COALESCE(payment_value, 0)) AS payment_total
    FROM dbo.order_payments GROUP BY order_id
),
Reconciliation AS
(
    SELECT o.order_id,
           COALESCE(i.item_total, 0) AS item_total,
           COALESCE(i.freight_total, 0) AS freight_total,
           COALESCE(i.item_total, 0) + COALESCE(i.freight_total, 0) AS items_plus_freight,
           COALESCE(p.payment_total, 0) AS payment_total,
           ROUND(COALESCE(p.payment_total, 0) - (COALESCE(i.item_total, 0) + COALESCE(i.freight_total, 0)), 2) AS difference
    FROM dbo.orders AS o
    LEFT JOIN ItemByOrder AS i ON i.order_id = o.order_id
    LEFT JOIN PaymentByOrder AS p ON p.order_id = o.order_id
)
SELECT order_id, item_total, freight_total, items_plus_freight, payment_total, difference,
       CASE WHEN ABS(difference) < 0.01 THEN 'Match'
            WHEN difference > 0 THEN 'Payment Higher'
            ELSE 'Payment Lower' END AS reconciliation_status
FROM Reconciliation
ORDER BY ABS(difference) DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 17
 What is the total value and count of orders with meaningful reconciliation gaps?
 Adjust the threshold (1.00) to match your business rule.
=============================================================================*/
;WITH ItemByOrder AS
(
    SELECT order_id, SUM(COALESCE(price, 0)) AS item_total,
           SUM(COALESCE(freight_value, 0)) AS freight_total
    FROM dbo.order_items GROUP BY order_id
),
PaymentByOrder AS
(
    SELECT order_id, SUM(COALESCE(payment_value, 0)) AS payment_total
    FROM dbo.order_payments GROUP BY order_id
),
Differences AS
(
    SELECT o.order_id,
           COALESCE(p.payment_total, 0) - (COALESCE(i.item_total, 0) + COALESCE(i.freight_total, 0)) AS difference
    FROM dbo.orders AS o
    LEFT JOIN ItemByOrder AS i ON i.order_id = o.order_id
    LEFT JOIN PaymentByOrder AS p ON p.order_id = o.order_id
)
SELECT CASE WHEN difference >= 1.00 THEN 'Payment Higher by >= 1'
            WHEN difference <= -1.00 THEN 'Payment Lower by >= 1'
            ELSE 'Within +/- 1' END AS difference_band,
       COUNT_BIG(*) AS order_count,
       SUM(difference) AS net_difference,
       SUM(ABS(difference)) AS absolute_difference_total
FROM Differences
GROUP BY CASE WHEN difference >= 1.00 THEN 'Payment Higher by >= 1'
              WHEN difference <= -1.00 THEN 'Payment Lower by >= 1'
              ELSE 'Within +/- 1' END
ORDER BY order_count DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 18
 Who are the most valuable repeat customers by total item sales?
 Customer identity uses customer_unique_id rather than customer_id.
=============================================================================*/
;WITH CustomerMap AS
(
    SELECT customer_id, MAX(customer_unique_id) AS customer_unique_id
    FROM dbo.customers GROUP BY customer_id
),
SalesByOrder AS
(
    SELECT order_id, SUM(COALESCE(price, 0)) AS item_sales,
           SUM(COALESCE(freight_value, 0)) AS freight_total
    FROM dbo.order_items GROUP BY order_id
),
CustomerOrders AS
(
    SELECT cm.customer_unique_id, o.order_id, o.order_purchase_timestamp,
           COALESCE(s.item_sales, 0) AS item_sales,
           COALESCE(s.freight_total, 0) AS freight_total
    FROM dbo.orders AS o
    JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
    LEFT JOIN SalesByOrder AS s ON s.order_id = o.order_id
)
SELECT TOP (20) customer_unique_id,
       COUNT_BIG(*) AS order_count,
       SUM(item_sales) AS lifetime_item_sales,
       SUM(freight_total) AS lifetime_freight,
       MIN(order_purchase_timestamp) AS first_order_date,
       MAX(order_purchase_timestamp) AS latest_order_date
FROM CustomerOrders
GROUP BY customer_unique_id
HAVING COUNT_BIG(*) > 1
ORDER BY lifetime_item_sales DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 19
 What is the first-versus-repeat order mix over time?
 ROW_NUMBER ranks each order per customer; COUNT over the order grain prevents
 product/payment lines from changing the count of orders.
=============================================================================*/
;WITH CustomerMap AS
(
    SELECT customer_id, MAX(customer_unique_id) AS customer_unique_id
    FROM dbo.customers GROUP BY customer_id
),
RankedOrders AS
(
    SELECT o.order_id, o.order_purchase_timestamp, cm.customer_unique_id,
           ROW_NUMBER() OVER (PARTITION BY cm.customer_unique_id
                              ORDER BY o.order_purchase_timestamp, o.order_id) AS customer_order_number
    FROM dbo.orders AS o
    JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
    WHERE cm.customer_unique_id IS NOT NULL
)
SELECT YEAR(order_purchase_timestamp) AS order_year,
       MONTH(order_purchase_timestamp) AS order_month,
       COUNT_BIG(*) AS total_orders,
       SUM(CASE WHEN customer_order_number = 1 THEN 1 ELSE 0 END) AS first_observed_orders,
       SUM(CASE WHEN customer_order_number > 1 THEN 1 ELSE 0 END) AS repeat_customer_orders,
       CAST(100.0 * SUM(CASE WHEN customer_order_number > 1 THEN 1 ELSE 0 END)
            / NULLIF(COUNT_BIG(*), 0) AS decimal(10,2)) AS repeat_order_share_pct
FROM RankedOrders
GROUP BY YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp)
ORDER BY order_year, order_month;
GO

/*=============================================================================
 BUSINESS QUESTION 20
 Rank states by item sales, with a running cumulative share (window functions).
=============================================================================*/
;WITH CustomerMap AS
(
    SELECT customer_id, MAX(customer_state) AS customer_state
    FROM dbo.customers GROUP BY customer_id
),
SalesByOrder AS
(
    SELECT order_id, SUM(COALESCE(price, 0)) AS item_sales
    FROM dbo.order_items GROUP BY order_id
),
StateSales AS
(
    SELECT COALESCE(cm.customer_state, N'(unknown)') AS customer_state,
           SUM(COALESCE(s.item_sales, 0)) AS item_sales,
           COUNT_BIG(*) AS total_orders
    FROM dbo.orders AS o
    LEFT JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
    LEFT JOIN SalesByOrder AS s ON s.order_id = o.order_id
    GROUP BY COALESCE(cm.customer_state, N'(unknown)')
)
SELECT customer_state, total_orders, item_sales,
       RANK() OVER (ORDER BY item_sales DESC) AS sales_rank,
       SUM(item_sales) OVER (ORDER BY item_sales DESC ROWS UNBOUNDED PRECEDING) AS cumulative_item_sales,
       CAST(100.0 * SUM(item_sales) OVER (ORDER BY item_sales DESC ROWS UNBOUNDED PRECEDING)
            / NULLIF(SUM(item_sales) OVER (), 0) AS decimal(10,2)) AS cumulative_sales_share_pct
FROM StateSales
ORDER BY sales_rank;
GO

/*=============================================================================
 BUSINESS QUESTION 21
 Which categories perform best inside each customer state? Uses RANK partitioned
 by state; item sales are attributed to the order's customer state.
=============================================================================*/
;WITH CustomerMap AS
(
    SELECT customer_id, MAX(customer_state) AS customer_state
    FROM dbo.customers GROUP BY customer_id
),
CategoryStateSales AS
(
    SELECT COALESCE(cm.customer_state, N'(unknown)') AS customer_state,
           COALESCE(ct.product_category_name_english, p.product_category_name, N'(unknown)') AS product_category,
           SUM(COALESCE(oi.price, 0)) AS item_sales,
           COUNT(DISTINCT oi.order_id) AS distinct_orders
    FROM dbo.order_items AS oi
    JOIN dbo.orders AS o ON o.order_id = oi.order_id
    LEFT JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
    JOIN dbo.products AS p ON p.product_id = oi.product_id
    LEFT JOIN dbo.category_translation AS ct ON ct.product_category_name = p.product_category_name
    GROUP BY COALESCE(cm.customer_state, N'(unknown)'),
             COALESCE(ct.product_category_name_english, p.product_category_name, N'(unknown)')
),
Ranked AS
(
    SELECT *, RANK() OVER (PARTITION BY customer_state ORDER BY item_sales DESC) AS category_rank
    FROM CategoryStateSales
)
SELECT customer_state, category_rank, product_category, item_sales, distinct_orders
FROM Ranked
WHERE category_rank <= 5
ORDER BY customer_state, category_rank;
GO

/*=============================================================================
 BUSINESS QUESTION 22
 What is the order approval and shipping wait-time distribution?
=============================================================================*/
SELECT
    CASE WHEN order_approved_at IS NULL OR order_purchase_timestamp IS NULL THEN 'Missing timestamp'
         WHEN DATEDIFF(HOUR, order_purchase_timestamp, order_approved_at) < 0 THEN 'Negative / invalid'
         WHEN DATEDIFF(HOUR, order_purchase_timestamp, order_approved_at) <= 24 THEN '0-24 hours'
         WHEN DATEDIFF(HOUR, order_purchase_timestamp, order_approved_at) <= 72 THEN '1-3 days'
         ELSE 'Over 3 days' END AS purchase_to_approval_band,
    COUNT_BIG(*) AS order_count
FROM dbo.orders
GROUP BY CASE WHEN order_approved_at IS NULL OR order_purchase_timestamp IS NULL THEN 'Missing timestamp'
              WHEN DATEDIFF(HOUR, order_purchase_timestamp, order_approved_at) < 0 THEN 'Negative / invalid'
              WHEN DATEDIFF(HOUR, order_purchase_timestamp, order_approved_at) <= 24 THEN '0-24 hours'
              WHEN DATEDIFF(HOUR, order_purchase_timestamp, order_approved_at) <= 72 THEN '1-3 days'
              ELSE 'Over 3 days' END
ORDER BY order_count DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 23
 What are the review scores for late vs on-time delivered orders?
 Average reviews per order first to prevent multiple review records duplicating
 the delivered-order grain.
=============================================================================*/
;WITH ReviewByOrder AS
(
    SELECT order_id, AVG(CAST(review_score AS decimal(10,2))) AS avg_review_score
    FROM dbo.order_reviews GROUP BY order_id
),
DeliveryReview AS
(
    SELECT o.order_id,
           CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Late'
                WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 'On time'
                ELSE 'Not comparable' END AS delivery_result,
           r.avg_review_score
    FROM dbo.orders AS o
    LEFT JOIN ReviewByOrder AS r ON r.order_id = o.order_id
)
SELECT delivery_result,
       COUNT_BIG(*) AS order_count,
       COUNT(avg_review_score) AS orders_with_reviews,
       CAST(AVG(avg_review_score) AS decimal(10,2)) AS avg_review_score
FROM DeliveryReview
GROUP BY delivery_result
ORDER BY avg_review_score DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 24
 Which order lines have missing or unusual product attributes?
 Product columns preserve Olist's original spellings: *_lenght.
=============================================================================*/
SELECT
    CASE WHEN product_name_lenght IS NULL
           OR product_description_lenght IS NULL
           OR product_photos_qty IS NULL
           OR product_weight_g IS NULL
           OR product_length_cm IS NULL
           OR product_height_cm IS NULL
           OR product_width_cm IS NULL THEN 'Missing attribute(s)'
         WHEN product_name_lenght <= 0
           OR product_description_lenght < 0
           OR product_photos_qty < 0
           OR product_weight_g <= 0
           OR product_length_cm <= 0
           OR product_height_cm <= 0
           OR product_width_cm <= 0 THEN 'Zero / negative attribute(s)'
         ELSE 'Complete / positive attributes' END AS product_attribute_quality,
       COUNT_BIG(*) AS product_count
FROM dbo.products
GROUP BY CASE WHEN product_name_lenght IS NULL
                OR product_description_lenght IS NULL
                OR product_photos_qty IS NULL
                OR product_weight_g IS NULL
                OR product_length_cm IS NULL
                OR product_height_cm IS NULL
                OR product_width_cm IS NULL THEN 'Missing attribute(s)'
              WHEN product_name_lenght <= 0
                OR product_description_lenght < 0
                OR product_photos_qty < 0
                OR product_weight_g <= 0
                OR product_length_cm <= 0
                OR product_height_cm <= 0
                OR product_width_cm <= 0 THEN 'Zero / negative attribute(s)'
              ELSE 'Complete / positive attributes' END
ORDER BY product_count DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 25 — DATA QUALITY
 Are any key business identifiers duplicated in the dimensions / fact tables?
 Each result set below should be reviewed; duplicates can invalidate 1:* joins.
=============================================================================*/
SELECT customer_id, COUNT_BIG(*) AS row_count
FROM dbo.customers
GROUP BY customer_id
HAVING COUNT_BIG(*) > 1
ORDER BY row_count DESC;
GO

SELECT order_id, COUNT_BIG(*) AS row_count
FROM dbo.orders
GROUP BY order_id
HAVING COUNT_BIG(*) > 1
ORDER BY row_count DESC;
GO

SELECT product_id, COUNT_BIG(*) AS row_count
FROM dbo.products
GROUP BY product_id
HAVING COUNT_BIG(*) > 1
ORDER BY row_count DESC;
GO

SELECT seller_id, COUNT_BIG(*) AS row_count
FROM dbo.sellers
GROUP BY seller_id
HAVING COUNT_BIG(*) > 1
ORDER BY row_count DESC;
GO

SELECT order_id, order_item_id, COUNT_BIG(*) AS row_count
FROM dbo.order_items
GROUP BY order_id, order_item_id
HAVING COUNT_BIG(*) > 1
ORDER BY row_count DESC;
GO

SELECT order_id, payment_sequential, COUNT_BIG(*) AS row_count
FROM dbo.order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT_BIG(*) > 1
ORDER BY row_count DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 26 — REFERENTIAL INTEGRITY
 Which fact rows refer to order/product/seller/customer keys absent from parent
 tables? These queries return problem records only.
=============================================================================*/
SELECT oi.*
FROM dbo.order_items AS oi
LEFT JOIN dbo.orders AS o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL;
GO

SELECT oi.*
FROM dbo.order_items AS oi
LEFT JOIN dbo.products AS p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL;
GO

SELECT oi.*
FROM dbo.order_items AS oi
LEFT JOIN dbo.sellers AS s ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL;
GO

SELECT o.*
FROM dbo.orders AS o
LEFT JOIN dbo.customers AS c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;
GO

SELECT pay.*
FROM dbo.order_payments AS pay
LEFT JOIN dbo.orders AS o ON o.order_id = pay.order_id
WHERE o.order_id IS NULL;
GO

SELECT r.*
FROM dbo.order_reviews AS r
LEFT JOIN dbo.orders AS o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;
GO

/*=============================================================================
 BUSINESS QUESTION 27 — DATE / DELIVERY DATA QUALITY
 How many orders have missing timestamps or an invalid chronological sequence?
=============================================================================*/
SELECT
    COUNT_BIG(*) AS total_orders,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS missing_purchase_timestamp,
    SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS missing_approval_timestamp,
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS missing_carrier_timestamp,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_customer_delivery_timestamp,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS missing_estimated_delivery_date,
    SUM(CASE WHEN order_approved_at < order_purchase_timestamp THEN 1 ELSE 0 END) AS approval_before_purchase,
    SUM(CASE WHEN order_delivered_carrier_date < order_approved_at THEN 1 ELSE 0 END) AS carrier_before_approval,
    SUM(CASE WHEN order_delivered_customer_date < order_delivered_carrier_date THEN 1 ELSE 0 END) AS customer_delivery_before_carrier
FROM dbo.orders;
GO

/*=============================================================================
 BUSINESS QUESTION 28 — DECISION SUPPORT
 What should be investigated first? This query returns the largest per-order
 payment-vs-items-plus-freight gaps with customer/state/status context.
=============================================================================*/
;WITH ItemByOrder AS
(
    SELECT order_id, SUM(COALESCE(price, 0)) AS item_total,
           SUM(COALESCE(freight_value, 0)) AS freight_total
    FROM dbo.order_items GROUP BY order_id
),
PaymentByOrder AS
(
    SELECT order_id, SUM(COALESCE(payment_value, 0)) AS payment_total
    FROM dbo.order_payments GROUP BY order_id
),
CustomerMap AS
(
    SELECT customer_id, MAX(customer_state) AS customer_state,
           MAX(customer_city) AS customer_city
    FROM dbo.customers GROUP BY customer_id
),
OrderGap AS
(
    SELECT o.order_id, o.order_status, o.order_purchase_timestamp,
           cm.customer_city, cm.customer_state,
           COALESCE(i.item_total, 0) AS item_total,
           COALESCE(i.freight_total, 0) AS freight_total,
           COALESCE(p.payment_total, 0) AS payment_total,
           ROUND(COALESCE(p.payment_total, 0) - COALESCE(i.item_total, 0) - COALESCE(i.freight_total, 0), 2) AS difference
    FROM dbo.orders AS o
    LEFT JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
    LEFT JOIN ItemByOrder AS i ON i.order_id = o.order_id
    LEFT JOIN PaymentByOrder AS p ON p.order_id = o.order_id
)
SELECT TOP (100) *,
       CASE WHEN ABS(difference) < 0.01 THEN 'Match'
            WHEN difference > 0 THEN 'Payment Higher'
            ELSE 'Payment Lower' END AS reconciliation_status
FROM OrderGap
WHERE ABS(difference) >= 1.00
ORDER BY ABS(difference) DESC;
GO

/*=============================================================================
 BUSINESS QUESTION 29 — EXPLICIT SUBQUERY
 Which customers place more orders than the average customer?
 The scalar subquery compares each customer's count with the overall average.
=============================================================================*/
;WITH CustomerMap AS
(
    SELECT customer_id, MAX(customer_unique_id) AS customer_unique_id
    FROM dbo.customers
    GROUP BY customer_id
),
CustomerOrderCounts AS
(
    SELECT cm.customer_unique_id,
           COUNT(DISTINCT o.order_id) AS order_count
    FROM dbo.orders AS o
    JOIN CustomerMap AS cm ON cm.customer_id = o.customer_id
    WHERE cm.customer_unique_id IS NOT NULL
    GROUP BY cm.customer_unique_id
)
SELECT customer_unique_id, order_count
FROM CustomerOrderCounts
WHERE order_count >
      (SELECT AVG(CAST(order_count AS decimal(18,2))) FROM CustomerOrderCounts)
ORDER BY order_count DESC, customer_unique_id;
GO

/*=============================================================================
 HOW TO INTERPRET RESULTS — IMPORTANT
 1) Do not label payment differences as profit/loss without checking vouchers,
    installments, cancellations, refunds, shipping, and data-cleaning changes.
 2) Do not join raw order_items directly to raw order_payments for monetary
    totals. Aggregate each table to order_id first, as shown above.
 3) Geolocation ZIP prefixes may not be unique in source data. Avoid assuming a
    simple unique ZIP relationship unless you validated/deduplicated it with a
    defensible rule.
 4) Use actual query results to write findings; the SQL file does not invent
    results or recommendations.
=============================================================================*/
