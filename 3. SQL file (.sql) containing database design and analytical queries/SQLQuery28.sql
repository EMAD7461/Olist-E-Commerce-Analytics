
USE OlistDB;
GO

CREATE OR ALTER VIEW dbo.vw_Order_Payments_Summary
AS
SELECT
    order_id,
    SUM(payment_value) AS Payment_Total
FROM dbo.order_payments
GROUP BY order_id;
GO
--

SELECT TOP (20)
    order_id,
    Payment_Total
FROM dbo.vw_Order_Payments_Summary
ORDER BY Payment_Total DESC;
GO
----

USE OlistDB;
GO

CREATE OR ALTER VIEW dbo.vw_Order_Reconciliation
AS
WITH ItemTotals AS
(
    SELECT
        order_id,
        SUM(CONVERT(DECIMAL(19,2), price)) AS Items_Total,
        SUM(CONVERT(DECIMAL(19,2), freight_value))
            AS Freight_Total
    FROM dbo.order_items
    GROUP BY order_id
),
PaymentTotals AS
(
    SELECT
        order_id,
        SUM(CONVERT(DECIMAL(19,2), payment_value))
            AS Payment_Total
    FROM dbo.order_payments
    GROUP BY order_id
)
SELECT
    o.order_id,
    COALESCE(i.Items_Total, CONVERT(DECIMAL(19,2), 0))
        AS Items_Total,
    COALESCE(i.Freight_Total, CONVERT(DECIMAL(19,2), 0))
        AS Freight_Total,

    COALESCE(i.Items_Total, CONVERT(DECIMAL(19,2), 0))
    + COALESCE(i.Freight_Total, CONVERT(DECIMAL(19,2), 0))
        AS Items_Freight_Total,

    COALESCE(p.Payment_Total, CONVERT(DECIMAL(19,2), 0))
        AS Payment_Total,

    COALESCE(p.Payment_Total, CONVERT(DECIMAL(19,2), 0))
    - COALESCE(i.Items_Total, CONVERT(DECIMAL(19,2), 0))
    - COALESCE(i.Freight_Total, CONVERT(DECIMAL(19,2), 0))
        AS Reconciliation_Difference

FROM dbo.orders AS o
LEFT JOIN ItemTotals AS i
    ON o.order_id = i.order_id
LEFT JOIN PaymentTotals AS p
    ON o.order_id = p.order_id;
GO


SELECT TOP (20)
    order_id,
    Items_Total,
    Freight_Total,
    Items_Freight_Total,
    Payment_Total,
    Reconciliation_Difference
FROM dbo.vw_Order_Reconciliation
ORDER BY ABS(Reconciliation_Difference) DESC;
GO

