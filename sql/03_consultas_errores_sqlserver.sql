-- =====================================================================
-- NORTHWIND TRADERS · CONSULTAS QUE MUESTRAN LOS ERRORES (SQL Server)
-- Cada consulta devuelve solo los registros con problema.
-- Si devuelve 0 filas, esa prueba está limpia.
-- Requieren las vistas de 01_vistas_sqlserver.sql
-- =====================================================================
-- Azure SQL no permite USE. Antes de ejecutar, elige la base
-- 'sqldb-invacom-fuente' en la lista desplegable de la barra de herramientas.

-- E0. TABLERO DE SALUD: un renglón por prueba con el número de casos
WITH checks AS (
  SELECT 'Claves foráneas huérfanas' AS check_name,
         (SELECT COUNT(*) FROM dbo.order_details od WHERE NOT EXISTS (SELECT 1 FROM dbo.orders o   WHERE o.orderID = od.orderID))
       + (SELECT COUNT(*) FROM dbo.order_details od WHERE NOT EXISTS (SELECT 1 FROM dbo.products p WHERE p.productID = od.productID))
       + (SELECT COUNT(*) FROM dbo.orders o WHERE NOT EXISTS (SELECT 1 FROM dbo.customers c WHERE c.customerID = o.customerID))
       + (SELECT COUNT(*) FROM dbo.orders o WHERE NOT EXISTS (SELECT 1 FROM dbo.employees e WHERE e.employeeID = o.employeeID))
       + (SELECT COUNT(*) FROM dbo.orders o WHERE NOT EXISTS (SELECT 1 FROM dbo.shippers s  WHERE s.shipperID  = o.shipperID))
       + (SELECT COUNT(*) FROM dbo.products p WHERE NOT EXISTS (SELECT 1 FROM dbo.categories c WHERE c.categoryID = p.categoryID)) AS cases
  UNION ALL SELECT 'Líneas duplicadas (orderID, productID)',
         (SELECT COUNT(*) FROM (SELECT 1 AS x FROM dbo.order_details GROUP BY orderID, productID HAVING COUNT(*) > 1) d)
  UNION ALL SELECT 'Fechas incoherentes',
         (SELECT COUNT(*) FROM dbo.orders WHERE shippedDate < orderDate OR requiredDate <= orderDate)
  UNION ALL SELECT 'Cantidad o precio inválido',
         (SELECT COUNT(*) FROM dbo.order_details WHERE quantity <= 0 OR unitPrice <= 0)
  UNION ALL SELECT 'Descuentos fuera de la política',
         (SELECT COUNT(*) FROM dbo.order_details WHERE discount NOT IN (0, 0.05, 0.10, 0.15, 0.20, 0.25))
  UNION ALL SELECT 'Precios fuera de los niveles 80% / 100%',
         (SELECT COUNT(*) FROM dbo.order_details od JOIN dbo.products p ON p.productID = od.productID
           WHERE ROUND(1.0 * od.unitPrice / p.unitPrice, 2) NOT IN (0.79, 0.80, 1.00))
  UNION ALL SELECT 'Pedidos con más de 10 líneas',
         (SELECT COUNT(*) FROM (SELECT 1 AS x FROM dbo.order_details GROUP BY orderID HAVING COUNT(*) > 10) d)
  UNION ALL SELECT 'Flete atípico (> 50% del valor o < $1)',
         (SELECT COUNT(*) FROM dbo.v_order_totals WHERE freight > 0.5 * net OR freight < 1)
  UNION ALL SELECT 'Envíos tardíos',
         (SELECT COUNT(*) FROM dbo.orders WHERE shippedDate > requiredDate)
  UNION ALL SELECT 'Pedidos sin fecha de envío',
         (SELECT COUNT(*) FROM dbo.orders WHERE shippedDate IS NULL)
  UNION ALL SELECT 'Clientes sin pedidos',
         (SELECT COUNT(*) FROM dbo.customers c WHERE NOT EXISTS (SELECT 1 FROM dbo.orders o WHERE o.customerID = c.customerID))
  UNION ALL SELECT 'Texto con espacios sobrantes o invisibles',
         (SELECT COUNT(*) FROM dbo.customers
           WHERE DATALENGTH(companyName) <> DATALENGTH(TRIM(companyName))   -- espacio al inicio o al final
              OR companyName LIKE '%  %'                                      -- doble espacio
              OR CHARINDEX(NCHAR(160), companyName) > 0                       -- espacio no separable
              OR CHARINDEX(CHAR(9), companyName) > 0)                         -- tabulador
       + (SELECT COUNT(*) FROM dbo.products
           WHERE DATALENGTH(productName) <> DATALENGTH(TRIM(productName))
              OR productName LIKE '%  %'
              OR CHARINDEX(NCHAR(160), productName) > 0
              OR CHARINDEX(CHAR(9), productName) > 0
              OR DATALENGTH(quantityPerUnit) <> DATALENGTH(TRIM(quantityPerUnit))
              OR quantityPerUnit LIKE '%  %')
  UNION ALL SELECT 'Valores compuestos en contactTitle',
         (SELECT COUNT(*) FROM dbo.customers WHERE contactTitle LIKE '%/%')
)
SELECT check_name, cases,
       CASE WHEN cases = 0 THEN 'OK' ELSE 'REVISAR' END AS status
FROM checks;

-- E1. Claves foráneas huérfanas (detalle; debe devolver 0 filas)
SELECT 'order_details → orders' AS relation, CAST(od.orderID AS NVARCHAR(50)) AS [key]
FROM dbo.order_details od
 WHERE NOT EXISTS (SELECT 1 FROM dbo.orders o WHERE o.orderID = od.orderID)
UNION ALL
SELECT 'order_details → products', CAST(od.productID AS NVARCHAR(50)) FROM dbo.order_details od
 WHERE NOT EXISTS (SELECT 1 FROM dbo.products p WHERE p.productID = od.productID)
UNION ALL
SELECT 'orders → customers', CAST(o.customerID AS NVARCHAR(50)) FROM dbo.orders o
 WHERE NOT EXISTS (SELECT 1 FROM dbo.customers c WHERE c.customerID = o.customerID)
UNION ALL
SELECT 'orders → employees', CAST(o.employeeID AS NVARCHAR(50)) FROM dbo.orders o
 WHERE NOT EXISTS (SELECT 1 FROM dbo.employees e WHERE e.employeeID = o.employeeID)
UNION ALL
SELECT 'orders → shippers', CAST(o.shipperID AS NVARCHAR(50)) FROM dbo.orders o
 WHERE NOT EXISTS (SELECT 1 FROM dbo.shippers s WHERE s.shipperID = o.shipperID)
UNION ALL
SELECT 'employees → employees (reportsTo)', CAST(e.reportsTo AS NVARCHAR(50)) FROM dbo.employees e
 WHERE e.reportsTo IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM dbo.employees m WHERE m.employeeID = e.reportsTo);

-- E2. Descuentos fuera de la política (0, 5, 10, 15, 20, 25 %)
SELECT od.orderID, p.productName, od.unitPrice, od.quantity,
       od.discount * 100 AS discount_pct
FROM dbo.order_details od
JOIN dbo.products p ON p.productID = od.productID
WHERE od.discount NOT IN (0, 0.05, 0.10, 0.15, 0.20, 0.25)
ORDER BY od.orderID, p.productName;

-- E3. Pedidos con un número anormal de líneas
SELECT orderID, customerID, orderDate, lines, net, ship_status
FROM dbo.v_order_totals
WHERE lines > 10
ORDER BY lines DESC;

-- E4. Precios vendidos que no corresponden a ningún nivel conocido
--     (ni precio actual ni precio anterior = 80% del actual)
SELECT od.orderID, o.orderDate, p.productName,
       od.unitPrice  AS sold_price,
       p.unitPrice   AS list_price,
       ROUND(100.0 * od.unitPrice / p.unitPrice, 1) AS pct_of_list
FROM dbo.order_details od
JOIN dbo.products p ON p.productID = od.productID
JOIN dbo.orders   o ON o.orderID   = od.orderID
WHERE ROUND(1.0 * od.unitPrice / p.unitPrice, 2) NOT IN (0.79, 0.80, 1.00)
ORDER BY od.orderID;

-- E5. Ventas al precio nuevo ANTES de que terminara el precio viejo
--     (incoherencia temporal de precios)
WITH old_price AS (
  SELECT od.productID, MAX(o.orderDate) AS last_old_price_date
  FROM dbo.order_details od
  JOIN dbo.orders   o ON o.orderID   = od.orderID
  JOIN dbo.products p ON p.productID = od.productID
  WHERE od.unitPrice < p.unitPrice
  GROUP BY od.productID
)
SELECT od.orderID, o.orderDate, p.productName, od.unitPrice, op.last_old_price_date
FROM dbo.order_details od
JOIN dbo.orders   o  ON o.orderID    = od.orderID
JOIN dbo.products p  ON p.productID  = od.productID
JOIN old_price    op ON op.productID = od.productID
WHERE od.unitPrice = p.unitPrice
  AND o.orderDate < op.last_old_price_date
ORDER BY o.orderDate;

-- E6. Flete atípico respecto del valor del pedido
SELECT orderID, orderDate, shipper, net, freight,
       ROUND(100.0 * freight / NULLIF(net, 0), 2) AS freight_pct_of_order,
       CASE WHEN freight > 0.5 * net THEN 'Flete excesivo' ELSE 'Flete casi nulo' END AS issue
FROM dbo.v_order_totals
WHERE freight > 0.5 * net OR freight < 1
ORDER BY freight_pct_of_order DESC;

-- E7. Envíos tardíos (días de atraso)
SELECT orderID, shipper, orderDate, requiredDate, shippedDate,
       DATEDIFF(DAY, requiredDate, shippedDate) AS days_late
FROM dbo.v_order_totals
WHERE ship_status = 'Tarde'
ORDER BY days_late DESC;

-- E8. Pedidos sin fecha de envío (y si ya vencieron al cierre de los datos: 1 = sí)
SELECT orderID, customerID, orderDate, requiredDate, freight,
       CASE WHEN requiredDate < (SELECT MAX(orderDate) FROM dbo.orders)
            THEN 1 ELSE 0 END AS overdue_at_data_cutoff
FROM dbo.orders
WHERE shippedDate IS NULL
ORDER BY orderDate;

-- E9. Clientes registrados que nunca compraron
SELECT c.customerID, c.companyName, c.city, c.country
FROM dbo.customers c
WHERE NOT EXISTS (SELECT 1 FROM dbo.orders o WHERE o.customerID = c.customerID);

-- E10. Texto con espacios dobles, al inicio/fin, tabuladores o espacio no separable (160)
SELECT 'customers.companyName' AS field, CAST(customerID AS NVARCHAR(50)) AS id, companyName AS value
FROM dbo.customers
WHERE DATALENGTH(companyName) <> DATALENGTH(TRIM(companyName))
   OR companyName LIKE '%  %'
   OR CHARINDEX(NCHAR(160), companyName) > 0
   OR CHARINDEX(CHAR(9), companyName) > 0
UNION ALL
SELECT 'products.productName', CAST(productID AS NVARCHAR(50)), productName
FROM dbo.products
WHERE DATALENGTH(productName) <> DATALENGTH(TRIM(productName))
   OR productName LIKE '%  %'
   OR CHARINDEX(NCHAR(160), productName) > 0
   OR CHARINDEX(CHAR(9), productName) > 0
UNION ALL
SELECT 'products.quantityPerUnit', CAST(productID AS NVARCHAR(50)), quantityPerUnit
FROM dbo.products
WHERE DATALENGTH(quantityPerUnit) <> DATALENGTH(TRIM(quantityPerUnit))
   OR quantityPerUnit LIKE '%  %';

-- E11. Valores compuestos (dos datos en un solo campo)
SELECT customerID, companyName, contactTitle
FROM dbo.customers
WHERE contactTitle LIKE '%/%';

-- E12. Campos de nombre no atómicos (nombre y apellido juntos)
--      Ojo: nombres compuestos como 'Miguel Angel Paolino' o
--      'Isabel de Castro' muestran por qué separar a mano no es confiable.
SELECT 'employees' AS source, employeeName AS full_name,
       LEFT(employeeName, CHARINDEX(' ', employeeName + ' ') - 1)              AS first_name,
       SUBSTRING(employeeName, CHARINDEX(' ', employeeName) + 1, LEN(employeeName)) AS last_name
FROM dbo.employees
UNION ALL
SELECT 'customers', contactName,
       LEFT(contactName, CHARINDEX(' ', contactName + ' ') - 1),
       SUBSTRING(contactName, CHARINDEX(' ', contactName) + 1, LEN(contactName))
FROM dbo.customers
ORDER BY source, full_name;

-- E13. Productos descontinuados con ventas en los últimos 90 días de datos
SELECT productName, last_sale, units, net_sales
FROM dbo.v_product_performance
WHERE is_discontinued = 1
  AND last_sale >= DATEADD(DAY, -90, (SELECT MAX(orderDate) FROM dbo.orders))
ORDER BY last_sale DESC;

-- E14. Formatos distintos en quantityPerUnit (texto libre, no numérico)
--      Cada número (entero o decimal) se reemplaza por 'N' para ver el patrón.
--      SQL Server 2022 no tiene REGEXP_REPLACE, así que se usa TRANSLATE + REPLACE.
SELECT pat.pattern,
       COUNT(*)                  AS products,
       MIN(p.quantityPerUnit)  AS example
FROM dbo.products p
CROSS APPLY (
  SELECT REPLACE(
           REPLACE(REPLACE(REPLACE(
             TRANSLATE(p.quantityPerUnit, '0123456789', '##########'),  -- dígitos → #
           '#', '<>'), '><', ''), '<>', 'N'),                               -- ### → N
         'N.N', 'N') AS pattern                                             -- 12.5 → N
) pat
GROUP BY pat.pattern
ORDER BY products DESC;
