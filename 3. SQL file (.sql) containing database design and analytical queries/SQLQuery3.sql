
-- Create the project database
IF DB_ID(N'OlistDB') IS NULL
    CREATE DATABASE OlistDB;
GO

USE OlistDB;
GO

-- Separate imported data from final tables
IF SCHEMA_ID(N'stg') IS NULL
    EXEC(N'CREATE SCHEMA stg');

IF SCHEMA_ID(N'dbo') IS NULL
    EXEC(N'CREATE SCHEMA dbo');
GO

SELECT TOP (10) *
FROM [OlistDB].[stg].[olist_customers_dataset];

USE OlistDB;
GO

-- Check row counts for all nine imported tables
SELECT 'customers' AS TableName, COUNT_BIG(*) AS TotalRows
FROM stg.customers
UNION ALL
SELECT 'geolocation', COUNT_BIG(*) FROM stg.geolocation
UNION ALL
SELECT 'order_items', COUNT_BIG(*) FROM stg.order_items
UNION ALL
SELECT 'order_payments', COUNT_BIG(*) FROM stg.order_payments
UNION ALL
SELECT 'order_reviews', COUNT_BIG(*) FROM stg.order_reviews
UNION ALL
SELECT 'orders', COUNT_BIG(*) FROM stg.orders
UNION ALL
SELECT 'products', COUNT_BIG(*) FROM stg.products
UNION ALL
SELECT 'sellers', COUNT_BIG(*) FROM stg.sellers
UNION ALL
SELECT 'category_translation', COUNT_BIG(*) FROM stg.category_translation;
GO

--------------

USE OlistDB;
GO

-- 1. Check single-column candidate keys
SELECT
    'customers.customer_id' AS KeyName,
    COUNT_BIG(*) AS TotalRows,
    COUNT_BIG(CASE WHEN customer_id IS NULL
        OR LTRIM(RTRIM(customer_id)) = '' THEN 1 END) AS InvalidKeys,
    COUNT_BIG(*) - COUNT_BIG(DISTINCT customer_id) AS DuplicateCount
FROM stg.customers

UNION ALL

SELECT
    'orders.order_id',
    COUNT_BIG(*),
    COUNT_BIG(CASE WHEN order_id IS NULL
        OR LTRIM(RTRIM(order_id)) = '' THEN 1 END),
    COUNT_BIG(*) - COUNT_BIG(DISTINCT order_id)
FROM stg.orders

UNION ALL

SELECT
    'products.product_id',
    COUNT_BIG(*),
    COUNT_BIG(CASE WHEN product_id IS NULL
        OR LTRIM(RTRIM(product_id)) = '' THEN 1 END),
    COUNT_BIG(*) - COUNT_BIG(DISTINCT product_id)
FROM stg.products

UNION ALL

SELECT
    'sellers.seller_id',
    COUNT_BIG(*),
    COUNT_BIG(CASE WHEN seller_id IS NULL
        OR LTRIM(RTRIM(seller_id)) = '' THEN 1 END),
    COUNT_BIG(*) - COUNT_BIG(DISTINCT seller_id)
FROM stg.sellers

UNION ALL

SELECT
    'order_reviews.review_id',
    COUNT_BIG(*),
    COUNT_BIG(CASE WHEN review_id IS NULL
        OR LTRIM(RTRIM(review_id)) = '' THEN 1 END),
    COUNT_BIG(*) - COUNT_BIG(DISTINCT review_id)
FROM stg.order_reviews;
GO
-----

USE OlistDB;
GO

-- Find duplicated review IDs
SELECT
    review_id,
    COUNT_BIG(*) AS Occurrences
FROM stg.order_reviews
GROUP BY review_id
HAVING COUNT_BIG(*) > 1
ORDER BY Occurrences DESC, review_id;
GO
----

USE OlistDB;
GO

-- Referential Integrity: check orphan records

SELECT
    'orders -> customers' AS RelationshipName,
    COUNT_BIG(*) AS OrphanRows
FROM stg.orders AS o
LEFT JOIN stg.customers AS c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL

SELECT
    'order_items -> orders',
    COUNT_BIG(*)
FROM stg.order_items AS oi
LEFT JOIN stg.orders AS o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT
    'order_items -> products',
    COUNT_BIG(*)
FROM stg.order_items AS oi
LEFT JOIN stg.products AS p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL

UNION ALL

SELECT
    'order_items -> sellers',
    COUNT_BIG(*)
FROM stg.order_items AS oi
LEFT JOIN stg.sellers AS s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL

UNION ALL

SELECT
    'order_payments -> orders',
    COUNT_BIG(*)
FROM stg.order_payments AS pay
LEFT JOIN stg.orders AS o
    ON pay.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT
    'order_reviews -> orders',
    COUNT_BIG(*)
FROM stg.order_reviews AS r
LEFT JOIN stg.orders AS o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;
GO
-----------

SELECT
    'customers' AS TableName,
    (SELECT COUNT_BIG(*) FROM stg.customers) AS StagingRows,
    (SELECT COUNT_BIG(*) FROM dbo.customers) AS FinalRows
UNION ALL
SELECT 'geolocation',
    (SELECT COUNT_BIG(*) FROM stg.geolocation),
    (SELECT COUNT_BIG(*) FROM dbo.geolocation)
UNION ALL
SELECT 'order_items',
    (SELECT COUNT_BIG(*) FROM stg.order_items),
    (SELECT COUNT_BIG(*) FROM dbo.order_items)
UNION ALL
SELECT 'order_payments',
    (SELECT COUNT_BIG(*) FROM stg.order_payments),
    (SELECT COUNT_BIG(*) FROM dbo.order_payments)
UNION ALL
SELECT 'order_reviews',
    (SELECT COUNT_BIG(*) FROM stg.order_reviews),
    (SELECT COUNT_BIG(*) FROM dbo.order_reviews)
UNION ALL
SELECT 'orders',
    (SELECT COUNT_BIG(*) FROM stg.orders),
    (SELECT COUNT_BIG(*) FROM dbo.orders)
UNION ALL
SELECT 'products',
    (SELECT COUNT_BIG(*) FROM stg.products),
    (SELECT COUNT_BIG(*) FROM dbo.products)
UNION ALL
SELECT 'sellers',
    (SELECT COUNT_BIG(*) FROM stg.sellers),
    (SELECT COUNT_BIG(*) FROM dbo.sellers)
UNION ALL
SELECT 'category_translation',
    (SELECT COUNT_BIG(*) FROM stg.category_translation),
    (SELECT COUNT_BIG(*) FROM dbo.category_translation);
GO
