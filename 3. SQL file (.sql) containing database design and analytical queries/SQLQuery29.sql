
USE OlistDB;
GO

SELECT
    'customers.customer_id' AS KeyName,
    COUNT_BIG(*) AS TotalRows,
    COUNT_BIG(CASE WHEN customer_id IS NULL
        OR LTRIM(RTRIM(customer_id)) = '' THEN 1 END) AS InvalidKeys,
    COUNT_BIG(*) - COUNT_BIG(DISTINCT customer_id) AS DuplicateCount
FROM dbo.customers

UNION ALL

SELECT
    'orders.order_id',
    COUNT_BIG(*),
    COUNT_BIG(CASE WHEN order_id IS NULL
        OR LTRIM(RTRIM(order_id)) = '' THEN 1 END),
    COUNT_BIG(*) - COUNT_BIG(DISTINCT order_id)
FROM dbo.orders

UNION ALL

SELECT
    'products.product_id',
    COUNT_BIG(*),
    COUNT_BIG(CASE WHEN product_id IS NULL
        OR LTRIM(RTRIM(product_id)) = '' THEN 1 END),
    COUNT_BIG(*) - COUNT_BIG(DISTINCT product_id)
FROM dbo.products

UNION ALL

SELECT
    'sellers.seller_id',
    COUNT_BIG(*),
    COUNT_BIG(CASE WHEN seller_id IS NULL
        OR LTRIM(RTRIM(seller_id)) = '' THEN 1 END),
    COUNT_BIG(*) - COUNT_BIG(DISTINCT seller_id)
FROM dbo.sellers;
GO

---------

USE OlistDB;
GO

-- 1. Check duplicate composite keys in order_items
SELECT
    'order_items' AS TableName,
    order_id,
    order_item_id AS SequenceID,
    COUNT_BIG(*) AS Occurrences
FROM dbo.order_items
GROUP BY order_id, order_item_id
HAVING COUNT_BIG(*) > 1;

-- 2. Check duplicate composite keys in order_payments
SELECT
    'order_payments' AS TableName,
    order_id,
    payment_sequential AS SequenceID,
    COUNT_BIG(*) AS Occurrences
FROM dbo.order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT_BIG(*) > 1;
GO

-- 3. Check missing values in the composite key columns
SELECT
    'order_items' AS TableName,
    COUNT_BIG(*) AS InvalidRows
FROM dbo.order_items
WHERE order_id IS NULL
   OR LTRIM(RTRIM(order_id)) = ''
   OR order_item_id IS NULL

UNION ALL

SELECT
    'order_payments',
    COUNT_BIG(*)
FROM dbo.order_payments
WHERE order_id IS NULL
   OR LTRIM(RTRIM(order_id)) = ''
   OR payment_sequential IS NULL;
GO
---------------

USE OlistDB;
GO

----------

USE OlistDB;
GO

SELECT
    fk.name AS ForeignKeyName,
    OBJECT_NAME(fk.parent_object_id) AS ChildTable,
    OBJECT_NAME(fk.referenced_object_id) AS ParentTable,
    fk.is_disabled AS IsDisabled,
    fk.is_not_trusted AS IsNotTrusted
FROM sys.foreign_keys AS fk
WHERE fk.name LIKE 'FK_%'
ORDER BY ChildTable, ForeignKeyName;
GO
-----------

USE OlistDB;
GO

SELECT
    t.name AS TableName,
    kc.name AS PrimaryKeyName,
    c.name AS ColumnName,
    ic.key_ordinal AS KeyPosition
FROM sys.key_constraints AS kc
JOIN sys.tables AS t
    ON t.object_id = kc.parent_object_id
JOIN sys.index_columns AS ic
    ON ic.object_id = t.object_id
   AND ic.index_id = kc.unique_index_id
JOIN sys.columns AS c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
WHERE kc.type = 'PK'
  AND SCHEMA_NAME(t.schema_id) = 'dbo'
ORDER BY t.name, ic.key_ordinal;
GO
-----------

USE OlistDB;
GO

-- Check uniqueness of the parent key
SELECT
    product_category_name,
    COUNT_BIG(*) AS Occurrences
FROM dbo.category_translation
GROUP BY product_category_name
HAVING product_category_name IS NULL
    OR LTRIM(RTRIM(product_category_name)) = ''
    OR COUNT_BIG(*) > 1;
GO

-- Check missing category translations
SELECT DISTINCT
    p.product_category_name
FROM dbo.products AS p
LEFT JOIN dbo.category_translation AS ct
    ON p.product_category_name = ct.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND LTRIM(RTRIM(p.product_category_name)) <> ''
  AND ct.product_category_name IS NULL;
GO
--------------
USE OlistDB;
GO


USE OlistDB;
GO

-- Check duplicate or empty category keys

USE OlistDB;
GO

-- Inspect the data types of zip code columns

USE OlistDB;
GO

-- Customer zip prefixes missing from geolocation
SELECT COUNT(DISTINCT c.customer_zip_code_prefix)
    AS MissingCustomerPrefixes
FROM dbo.customers AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.geolocation AS g
    WHERE g.geolocation_zip_code_prefix =
          c.customer_zip_code_prefix
);

-- Seller zip prefixes missing from geolocation
SELECT COUNT(DISTINCT s.seller_zip_code_prefix)
    AS MissingSellerPrefixes
FROM dbo.sellers AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.geolocation AS g
    WHERE g.geolocation_zip_code_prefix =
          s.seller_zip_code_prefix
);
GO
