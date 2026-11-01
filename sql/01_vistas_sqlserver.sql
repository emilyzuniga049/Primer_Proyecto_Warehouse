-- =====================================================================
-- NORTHWIND TRADERS · VISTAS DE ANÁLISIS (SQL Server / T-SQL)
-- Solo lectura: las vistas no modifican ni duplican datos.
-- Ejecutar el script completo (F5). Cada vista va separada por GO.
-- =====================================================================
-- Azure SQL no permite USE. Antes de ejecutar, elige la base
-- 'sqldb-invacom-fuente' en la lista desplegable de la barra de herramientas.

-- V1. Detalle de cada línea de pedido con todo su contexto
CREATE OR ALTER VIEW dbo.v_order_lines AS
SELECT od.orderID,
       o.orderDate,
       c.customerID,
       c.companyName     AS customer,
       c.country,
       e.employeeName    AS employee,
       p.productName     AS product,
       cat.categoryName  AS category,
       od.unitPrice,
       p.unitPrice       AS list_price,
       od.quantity,
       od.discount,
       ROUND(od.unitPrice * od.quantity, 2)                     AS gross,
       ROUND(od.unitPrice * od.quantity * (1 - od.discount), 2) AS net
FROM dbo.order_details od
JOIN dbo.orders     o   ON o.orderID      = od.orderID
JOIN dbo.products   p   ON p.productID    = od.productID
JOIN dbo.categories cat ON cat.categoryID = p.categoryID
JOIN dbo.customers  c   ON c.customerID   = o.customerID
JOIN dbo.employees  e   ON e.employeeID   = o.employeeID;
GO

-- V2. Un renglón por pedido: totales, flete, tiempos y estado del envío
CREATE OR ALTER VIEW dbo.v_order_totals AS
SELECT o.orderID,
       o.customerID,
       o.employeeID,
       s.companyName  AS shipper,
       o.orderDate, o.requiredDate, o.shippedDate,
       COUNT(*)                                                       AS lines,
       ROUND(SUM(od.unitPrice * od.quantity), 2)                     AS gross,
       ROUND(SUM(od.unitPrice * od.quantity * od.discount), 2)       AS discount_amount,
       ROUND(SUM(od.unitPrice * od.quantity * (1 - od.discount)), 2) AS net,
       o.freight,
       DATEDIFF(DAY, o.orderDate, o.shippedDate)  AS days_to_ship,
       CASE WHEN o.shippedDate IS NULL           THEN 'Pendiente'
            WHEN o.shippedDate > o.requiredDate THEN 'Tarde'
            ELSE 'A tiempo' END                   AS ship_status
FROM dbo.orders o
JOIN dbo.order_details od ON od.orderID  = o.orderID
JOIN dbo.shippers      s  ON s.shipperID = o.shipperID
GROUP BY o.orderID, o.customerID, o.employeeID, s.companyName,
         o.orderDate, o.requiredDate, o.shippedDate, o.freight;
GO

-- V3. Ventas por mes (con bandera de mes incompleto: 1 = incompleto)
CREATE OR ALTER VIEW dbo.v_monthly_sales AS
SELECT x.[month],
       COUNT(*)              AS orders,
       SUM(x.net)            AS net_sales,
       ROUND(AVG(x.net), 2)  AS avg_ticket,
       CASE WHEN x.[month] = mx.last_month THEN 1 ELSE 0 END AS incomplete_month
FROM (SELECT DATEFROMPARTS(YEAR(orderDate), MONTH(orderDate), 1) AS [month], net
      FROM dbo.v_order_totals) x
CROSS JOIN (SELECT DATEFROMPARTS(YEAR(MAX(orderDate)), MONTH(MAX(orderDate)), 1) AS last_month
            FROM dbo.orders) mx
GROUP BY x.[month], mx.last_month;
GO

-- V4. Ventas por categoría con participación
CREATE OR ALTER VIEW dbo.v_category_sales AS
SELECT category,
       SUM(quantity)                                     AS units,
       SUM(net)                                          AS net_sales,
       ROUND(100 * SUM(net) / SUM(SUM(net)) OVER (), 1)  AS pct_of_total
FROM dbo.v_order_lines
GROUP BY category;
GO

-- V5. Desempeño de cada producto
CREATE OR ALTER VIEW dbo.v_product_performance AS
SELECT p.productID, p.productName, cat.categoryName AS category,
       p.unitPrice                 AS list_price,
       p.discontinued               AS is_discontinued,
       COUNT(DISTINCT od.orderID)  AS orders,
       SUM(od.quantity)             AS units,
       ROUND(SUM(od.unitPrice * od.quantity * (1 - od.discount)), 2) AS net_sales,
       MIN(o.orderDate)  AS first_sale,
       MAX(o.orderDate)  AS last_sale
FROM dbo.products p
JOIN dbo.categories cat        ON cat.categoryID = p.categoryID
LEFT JOIN dbo.order_details od ON od.productID  = p.productID
LEFT JOIN dbo.orders o         ON o.orderID     = od.orderID
GROUP BY p.productID, p.productName, cat.categoryName, p.unitPrice, p.discontinued;
GO

-- V6. Resumen por cliente con ranking y % acumulado (Pareto)
CREATE OR ALTER VIEW dbo.v_customer_summary AS
WITH t AS (
  SELECT c.customerID, c.companyName, c.country,
         COUNT(ot.orderID)        AS orders,
         COALESCE(SUM(ot.net), 0)  AS net_sales,
         MIN(ot.orderDate)        AS first_order,
         MAX(ot.orderDate)        AS last_order
  FROM dbo.customers c
  LEFT JOIN dbo.v_order_totals ot ON ot.customerID = c.customerID
  GROUP BY c.customerID, c.companyName, c.country
)
SELECT t.*,
       RANK() OVER (ORDER BY net_sales DESC)  AS sales_rank,
       ROUND(100 * SUM(net_sales) OVER (ORDER BY net_sales DESC, customerID
                                        ROWS UNBOUNDED PRECEDING)
                 / SUM(net_sales) OVER (), 1)  AS cumulative_pct
FROM t;
GO

-- V7. Desempeño por vendedor, con su jefe
CREATE OR ALTER VIEW dbo.v_employee_performance AS
SELECT e.employeeID, e.employeeName, e.title, e.country,
       m.employeeName        AS manager,
       COUNT(ot.orderID)     AS orders,
       SUM(ot.net)            AS net_sales,
       ROUND(AVG(ot.net), 2)  AS avg_ticket
FROM dbo.employees e
LEFT JOIN dbo.employees m       ON m.employeeID  = e.reportsTo
LEFT JOIN dbo.v_order_totals ot ON ot.employeeID = e.employeeID
GROUP BY e.employeeID, e.employeeName, e.title, e.country, m.employeeName;
GO

-- V8. Desempeño de transportistas
CREATE OR ALTER VIEW dbo.v_shipper_performance AS
SELECT shipper,
       COUNT(*)                                                AS orders,
       ROUND(AVG(freight), 2)                                  AS avg_freight,
       ROUND(AVG(CAST(days_to_ship AS DECIMAL(10,2))), 1)      AS avg_days_to_ship,
       ROUND(100.0 * SUM(CASE WHEN ship_status = 'Tarde' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN ship_status <> 'Pendiente' THEN 1 ELSE 0 END), 0), 1) AS pct_late,
       SUM(CASE WHEN ship_status = 'Pendiente' THEN 1 ELSE 0 END)  AS pending
FROM dbo.v_order_totals
GROUP BY shipper;
GO

-- V9. Ventas por país
CREATE OR ALTER VIEW dbo.v_country_sales AS
SELECT country,
       COUNT(DISTINCT customerID)                       AS customers,
       COUNT(DISTINCT orderID)                          AS orders,
       SUM(net)                                          AS net_sales,
       ROUND(100 * SUM(net) / SUM(SUM(net)) OVER (), 1)  AS pct_of_total
FROM dbo.v_order_lines
GROUP BY country;
GO

-- V10. Historia de precios reconstruida desde order_details
--      (cada precio distinto que tuvo un producto y cuándo se usó)
CREATE OR ALTER VIEW dbo.v_product_price_history AS
SELECT p.productID, p.productName,
       od.unitPrice                                              AS price,
       p.unitPrice                                               AS current_list_price,
       ROUND(100.0 * od.unitPrice / NULLIF(p.unitPrice, 0), 1)  AS pct_of_list,
       MIN(o.orderDate)                                          AS valid_from,
       MAX(o.orderDate)                                          AS valid_to,
       COUNT(*)                                                   AS lines
FROM dbo.order_details od
JOIN dbo.orders   o ON o.orderID   = od.orderID
JOIN dbo.products p ON p.productID = od.productID
GROUP BY p.productID, p.productName, od.unitPrice, p.unitPrice;
GO
