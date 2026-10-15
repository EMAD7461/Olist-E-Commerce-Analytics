/* Olist E-commerce SQL Analysis | SQL Server | Database: OlistDB
   Assumes standard Olist column names and dbo schema. Review table names if yours differ.
   Item revenue = SUM(order_items.price); freight = SUM(freight_value);
   payment value = SUM(order_payments.payment_value). Do not add payments to item revenue.
*/
USE OlistDB;
GO

/* 0. Confirm imported tables */
SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA,TABLE_NAME;
GO

/* 1. Executive KPIs */
SELECT
 (SELECT COUNT_BIG(*) FROM dbo.orders) AS TotalOrders,
 (SELECT COUNT_BIG(DISTINCT customer_id) FROM dbo.orders) AS CustomersWhoOrdered,
 (SELECT COUNT_BIG(*) FROM dbo.products) AS Products,
 (SELECT COUNT_BIG(*) FROM dbo.sellers) AS Sellers,
 (SELECT COUNT_BIG(*) FROM dbo.order_items) AS OrderItemRows,
 (SELECT COUNT_BIG(*) FROM dbo.order_payments) AS PaymentRows;
GO

/* 2. Order status distribution */
SELECT order_status, COUNT_BIG(*) AS OrderCount,
 CAST(100.0*COUNT_BIG(*)/NULLIF(SUM(COUNT_BIG(*)) OVER(),0) AS DECIMAL(6,2)) AS PercentOfOrders
FROM dbo.orders GROUP BY order_status ORDER BY OrderCount DESC;
GO

/* 3. Monthly order trend */
SELECT DATEFROMPARTS(YEAR(order_purchase_timestamp),MONTH(order_purchase_timestamp),1) AS PurchaseMonth,
 COUNT_BIG(*) AS Orders, COUNT_BIG(DISTINCT customer_id) AS Customers
FROM dbo.orders WHERE order_purchase_timestamp IS NOT NULL
GROUP BY DATEFROMPARTS(YEAR(order_purchase_timestamp),MONTH(order_purchase_timestamp),1) ORDER BY PurchaseMonth;
GO

/* 4. Monthly sales and freight; aggregate items before joining to orders */
WITH ItemTotals AS (
 SELECT order_id, SUM(CAST(price AS DECIMAL(18,2))) AS ItemRevenue,
        SUM(CAST(freight_value AS DECIMAL(18,2))) AS FreightValue
 FROM dbo.order_items GROUP BY order_id
)
SELECT DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1) AS PurchaseMonth,
 COUNT_BIG(*) AS Orders, SUM(COALESCE(i.ItemRevenue,0)) AS ItemRevenue,
 SUM(COALESCE(i.FreightValue,0)) AS FreightValue,
 SUM(COALESCE(i.ItemRevenue,0)+COALESCE(i.FreightValue,0)) AS ItemPlusFreight
FROM dbo.orders o LEFT JOIN ItemTotals i ON i.order_id=o.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1)
ORDER BY PurchaseMonth;
GO

/* 5. Payment method mix */
SELECT payment_type, COUNT_BIG(*) AS PaymentRecords,
 SUM(CAST(payment_value AS DECIMAL(18,2))) AS PaymentValue,
 AVG(CAST(payment_value AS DECIMAL(18,2))) AS AvgPaymentRecordValue
FROM dbo.order_payments GROUP BY payment_type ORDER BY PaymentValue DESC;
GO

/* 6. Installments */
SELECT payment_installments, COUNT_BIG(*) AS PaymentRecords,
 SUM(CAST(payment_value AS DECIMAL(18,2))) AS PaymentValue
FROM dbo.order_payments GROUP BY payment_installments ORDER BY payment_installments;
GO

/* 7. Order-level financial reconciliation; item and payment totals are aggregated separately */
WITH ItemTotals AS (
 SELECT order_id,SUM(CAST(price AS DECIMAL(18,2))) AS ItemRevenue,
 SUM(CAST(freight_value AS DECIMAL(18,2))) AS FreightValue FROM dbo.order_items GROUP BY order_id
), PaymentTotals AS (
 SELECT order_id,SUM(CAST(payment_value AS DECIMAL(18,2))) AS PaymentValue,
 COUNT_BIG(*) AS PaymentRecords FROM dbo.order_payments GROUP BY order_id
)
SELECT o.order_id,o.order_status,COALESCE(i.ItemRevenue,0) AS ItemRevenue,
 COALESCE(i.FreightValue,0) AS FreightValue,
 COALESCE(i.ItemRevenue,0)+COALESCE(i.FreightValue,0) AS ItemPlusFreight,
 COALESCE(p.PaymentValue,0) AS PaymentValue,
 COALESCE(p.PaymentValue,0)-COALESCE(i.ItemRevenue,0)-COALESCE(i.FreightValue,0) AS PaymentDifference,
 COALESCE(p.PaymentRecords,0) AS PaymentRecords
FROM dbo.orders o LEFT JOIN ItemTotals i ON i.order_id=o.order_id
LEFT JOIN PaymentTotals p ON p.order_id=o.order_id
ORDER BY ABS(COALESCE(p.PaymentValue,0)-COALESCE(i.ItemRevenue,0)-COALESCE(i.FreightValue,0)) DESC;
GO

/* 8. Reconciliation summary by order status */
WITH I AS (SELECT order_id,SUM(CAST(price AS DECIMAL(18,2))) AS ItemRevenue,
 SUM(CAST(freight_value AS DECIMAL(18,2))) AS FreightValue FROM dbo.order_items GROUP BY order_id),
P AS (SELECT order_id,SUM(CAST(payment_value AS DECIMAL(18,2))) AS PaymentValue FROM dbo.order_payments GROUP BY order_id)
SELECT o.order_status,COUNT_BIG(*) AS Orders,SUM(COALESCE(I.ItemRevenue,0)) AS ItemRevenue,
 SUM(COALESCE(I.FreightValue,0)) AS FreightValue,SUM(COALESCE(P.PaymentValue,0)) AS PaymentValue,
 AVG(COALESCE(P.PaymentValue,0)-COALESCE(I.ItemRevenue,0)-COALESCE(I.FreightValue,0)) AS AvgPaymentDifference
FROM dbo.orders o LEFT JOIN I ON I.order_id=o.order_id LEFT JOIN P ON P.order_id=o.order_id
GROUP BY o.order_status ORDER BY Orders DESC;
GO

/* 9. Top 20 categories by item revenue */
SELECT TOP (20) COALESCE(t.product_category_name_english,p.product_category_name) AS CategoryName,
 COUNT_BIG(DISTINCT oi.order_id) AS Orders,COUNT_BIG(*) AS ItemsSold,
 SUM(CAST(oi.price AS DECIMAL(18,2))) AS ItemRevenue,
 SUM(CAST(oi.freight_value AS DECIMAL(18,2))) AS FreightValue
FROM dbo.order_items oi JOIN dbo.products p ON p.product_id=oi.product_id
LEFT JOIN dbo.product_category_name_translation t ON t.product_category_name=p.product_category_name
GROUP BY COALESCE(t.product_category_name_english,p.product_category_name)
ORDER BY ItemRevenue DESC;
GO

/* 10. Category performance by month */
SELECT DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1) AS PurchaseMonth,
 COALESCE(t.product_category_name_english,p.product_category_name) AS CategoryName,
 SUM(CAST(oi.price AS DECIMAL(18,2))) AS ItemRevenue,COUNT_BIG(*) AS ItemsSold
FROM dbo.orders o JOIN dbo.order_items oi ON oi.order_id=o.order_id
JOIN dbo.products p ON p.product_id=oi.product_id
LEFT JOIN dbo.product_category_name_translation t ON t.product_category_name=p.product_category_name
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1),
 COALESCE(t.product_category_name_english,p.product_category_name)
ORDER BY PurchaseMonth,ItemRevenue DESC;
GO

/* 11. Customer state performance */
WITH CR AS (
 SELECT o.customer_id,COUNT_BIG(DISTINCT o.order_id) AS Orders,
 SUM(CAST(oi.price AS DECIMAL(18,2))) AS ItemRevenue
 FROM dbo.orders o JOIN dbo.order_items oi ON oi.order_id=o.order_id GROUP BY o.customer_id
)
SELECT c.customer_state,COUNT_BIG(DISTINCT c.customer_unique_id) AS UniqueCustomers,
 SUM(COALESCE(CR.Orders,0)) AS Orders,SUM(COALESCE(CR.ItemRevenue,0)) AS ItemRevenue
FROM dbo.customers c LEFT JOIN CR ON CR.customer_id=c.customer_id
GROUP BY c.customer_state ORDER BY ItemRevenue DESC;
GO

/* 12. Repeat-purchase behavior, using customer_unique_id */
WITH CustomerOrderCounts AS (
 SELECT c.customer_unique_id,COUNT_BIG(*) AS OrderCount
 FROM dbo.orders o JOIN dbo.customers c ON c.customer_id=o.customer_id
 GROUP BY c.customer_unique_id
)
SELECT CASE WHEN OrderCount=1 THEN 'One order' ELSE 'Repeat customer' END AS CustomerType,
 COUNT_BIG(*) AS Customers,
 CAST(100.0*COUNT_BIG(*)/NULLIF(SUM(COUNT_BIG(*)) OVER(),0) AS DECIMAL(6,2)) AS PercentOfCustomers
FROM CustomerOrderCounts GROUP BY CASE WHEN OrderCount=1 THEN 'One order' ELSE 'Repeat customer' END;
GO

/* 13. Top 20 sellers by item revenue */
SELECT TOP (20) s.seller_id,s.seller_state,COUNT_BIG(DISTINCT oi.order_id) AS Orders,
 COUNT_BIG(*) AS ItemsSold,SUM(CAST(oi.price AS DECIMAL(18,2))) AS ItemRevenue,
 SUM(CAST(oi.freight_value AS DECIMAL(18,2))) AS FreightValue
FROM dbo.sellers s JOIN dbo.order_items oi ON oi.seller_id=s.seller_id
GROUP BY s.seller_id,s.seller_state ORDER BY ItemRevenue DESC;
GO

/* 14. Delivery time and on-time delivery rate */
WITH D AS (
 SELECT order_id,DATEDIFF(DAY,order_purchase_timestamp,order_delivered_customer_date) AS DeliveryDays,
 CASE WHEN order_delivered_customer_date<=order_estimated_delivery_date THEN 1 ELSE 0 END AS OnTime
 FROM dbo.orders WHERE order_purchase_timestamp IS NOT NULL AND order_delivered_customer_date IS NOT NULL
 AND order_estimated_delivery_date IS NOT NULL
)
SELECT COUNT_BIG(*) AS DeliveredOrders,AVG(CAST(DeliveryDays AS DECIMAL(10,2))) AS AvgDeliveryDays,
 SUM(OnTime) AS OnTimeOrders,
 CAST(100.0*SUM(OnTime)/NULLIF(COUNT_BIG(*),0) AS DECIMAL(6,2)) AS OnTimePercent
FROM D;
GO

/* 15. Delivery performance by customer state */
SELECT c.customer_state,COUNT_BIG(*) AS DeliveredOrders,
 AVG(CAST(DATEDIFF(DAY,o.order_purchase_timestamp,o.order_delivered_customer_date) AS DECIMAL(10,2))) AS AvgDeliveryDays,
 CAST(100.0*SUM(CASE WHEN o.order_delivered_customer_date<=o.order_estimated_delivery_date THEN 1 ELSE 0 END)
 /NULLIF(COUNT_BIG(*),0) AS DECIMAL(6,2)) AS OnTimePercent
FROM dbo.orders o JOIN dbo.customers c ON c.customer_id=o.customer_id
WHERE o.order_purchase_timestamp IS NOT NULL AND o.order_delivered_customer_date IS NOT NULL
AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state ORDER BY AvgDeliveryDays DESC;
GO

/* 16. Review score distribution */
SELECT review_score,COUNT_BIG(*) AS ReviewCount,
 CAST(100.0*COUNT_BIG(*)/NULLIF(SUM(COUNT_BIG(*)) OVER(),0) AS DECIMAL(6,2)) AS PercentOfReviews
FROM dbo.order_reviews GROUP BY review_score ORDER BY review_score;
GO

/* 17. Review score compared with delivery timing */
WITH R AS (SELECT order_id,AVG(CAST(review_score AS DECIMAL(10,2))) AS AvgReview FROM dbo.order_reviews GROUP BY order_id)
SELECT CASE WHEN o.order_delivered_customer_date IS NULL OR o.order_estimated_delivery_date IS NULL THEN 'Date unavailable'
 WHEN o.order_delivered_customer_date<=o.order_estimated_delivery_date THEN 'On time' ELSE 'Late' END AS DeliveryGroup,
 COUNT_BIG(*) AS Orders,AVG(R.AvgReview) AS AvgReviewScore
FROM dbo.orders o JOIN R ON R.order_id=o.order_id
GROUP BY CASE WHEN o.order_delivered_customer_date IS NULL OR o.order_estimated_delivery_date IS NULL THEN 'Date unavailable'
 WHEN o.order_delivered_customer_date<=o.order_estimated_delivery_date THEN 'On time' ELSE 'Late' END
ORDER BY AvgReviewScore DESC;
GO

/* 18. Month-over-month item revenue change: CTE + LAG */
WITH M AS (
 SELECT DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1) AS PurchaseMonth,
 SUM(CAST(oi.price AS DECIMAL(18,2))) AS ItemRevenue
 FROM dbo.orders o JOIN dbo.order_items oi ON oi.order_id=o.order_id
 WHERE o.order_purchase_timestamp IS NOT NULL
 GROUP BY DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1)
), P AS (
 SELECT *,LAG(ItemRevenue) OVER(ORDER BY PurchaseMonth) AS PreviousMonthRevenue FROM M
)
SELECT PurchaseMonth,ItemRevenue,PreviousMonthRevenue,ItemRevenue-PreviousMonthRevenue AS RevenueChange,
 CAST(100.0*(ItemRevenue-PreviousMonthRevenue)/NULLIF(PreviousMonthRevenue,0) AS DECIMAL(10,2)) AS RevenueChangePercent
FROM P ORDER BY PurchaseMonth;
GO

/* 19. Top 5 categories per month: CTE + DENSE_RANK */
WITH C AS (
 SELECT DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1) AS PurchaseMonth,
 COALESCE(t.product_category_name_english,p.product_category_name) AS CategoryName,
 SUM(CAST(oi.price AS DECIMAL(18,2))) AS ItemRevenue
 FROM dbo.orders o JOIN dbo.order_items oi ON oi.order_id=o.order_id
 JOIN dbo.products p ON p.product_id=oi.product_id
 LEFT JOIN dbo.product_category_name_translation t ON t.product_category_name=p.product_category_name
 WHERE o.order_purchase_timestamp IS NOT NULL
 GROUP BY DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1),
 COALESCE(t.product_category_name_english,p.product_category_name)
), R AS (SELECT *,DENSE_RANK() OVER(PARTITION BY PurchaseMonth ORDER BY ItemRevenue DESC) AS CategoryRank FROM C)
SELECT PurchaseMonth,CategoryName,ItemRevenue,CategoryRank FROM R WHERE CategoryRank<=5 ORDER BY PurchaseMonth,CategoryRank;
GO

/* 20. Cumulative revenue contribution by category */
WITH C AS (
 SELECT COALESCE(t.product_category_name_english,p.product_category_name) AS CategoryName,
 SUM(CAST(oi.price AS DECIMAL(18,2))) AS ItemRevenue
 FROM dbo.order_items oi JOIN dbo.products p ON p.product_id=oi.product_id
 LEFT JOIN dbo.product_category_name_translation t ON t.product_category_name=p.product_category_name
 GROUP BY COALESCE(t.product_category_name_english,p.product_category_name)
), R AS (
 SELECT *,SUM(ItemRevenue) OVER(ORDER BY ItemRevenue DESC ROWS UNBOUNDED PRECEDING) AS CumulativeRevenue,
 SUM(ItemRevenue) OVER() AS TotalRevenue FROM C
)
SELECT CategoryName,ItemRevenue,CumulativeRevenue,TotalRevenue,
 CAST(100.0*ItemRevenue/NULLIF(TotalRevenue,0) AS DECIMAL(8,2)) AS RevenuePercent,
 CAST(100.0*CumulativeRevenue/NULLIF(TotalRevenue,0) AS DECIMAL(8,2)) AS CumulativeRevenuePercent
FROM R ORDER BY ItemRevenue DESC;
GO

/* 21. Data quality: missing timestamps */
SELECT COUNT_BIG(*) AS TotalOrders,
 SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS MissingPurchaseTimestamp,
 SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS MissingApprovalTimestamp,
 SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS MissingCarrierDate,
 SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS MissingDeliveryDate,
 SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS MissingEstimatedDate
FROM dbo.orders;
GO

/* 22. Orders with no item rows or no payment rows */
WITH I AS (SELECT DISTINCT order_id FROM dbo.order_items), P AS (SELECT DISTINCT order_id FROM dbo.order_payments)
SELECT COUNT_BIG(*) AS TotalOrders,
 SUM(CASE WHEN I.order_id IS NULL THEN 1 ELSE 0 END) AS OrdersWithoutItems,
 SUM(CASE WHEN P.order_id IS NULL THEN 1 ELSE 0 END) AS OrdersWithoutPayments
FROM dbo.orders o LEFT JOIN I ON I.order_id=o.order_id LEFT JOIN P ON P.order_id=o.order_id;
GO

/* 23. Duplicate key checks */
SELECT 'orders.order_id' AS KeyName,COUNT_BIG(*) AS DuplicateGroups FROM
 (SELECT order_id FROM dbo.orders GROUP BY order_id HAVING COUNT_BIG(*)>1) d
UNION ALL SELECT 'customers.customer_id',COUNT_BIG(*) FROM
 (SELECT customer_id FROM dbo.customers GROUP BY customer_id HAVING COUNT_BIG(*)>1) d
UNION ALL SELECT 'products.product_id',COUNT_BIG(*) FROM
 (SELECT product_id FROM dbo.products GROUP BY product_id HAVING COUNT_BIG(*)>1) d
UNION ALL SELECT 'sellers.seller_id',COUNT_BIG(*) FROM
 (SELECT seller_id FROM dbo.sellers GROUP BY seller_id HAVING COUNT_BIG(*)>1) d;
GO

/* 24. Final financial control totals; compare with Python/Power Query validation */
SELECT
 (SELECT SUM(CAST(price AS DECIMAL(18,2))) FROM dbo.order_items) AS TotalItemPrice,
 (SELECT SUM(CAST(freight_value AS DECIMAL(18,2))) FROM dbo.order_items) AS TotalFreight,
 (SELECT SUM(CAST(price AS DECIMAL(18,2))+CAST(freight_value AS DECIMAL(18,2))) FROM dbo.order_items) AS TotalItemPlusFreight,
 (SELECT SUM(CAST(payment_value AS DECIMAL(18,2))) FROM dbo.order_payments) AS TotalPaymentValue;
GO
