-- =====================================================================
-- NORTHWIND TRADERS · CONSULTAS PARA EXPLORAR LOS DATOS (SQL Server)
-- Requieren las vistas de 01_vistas_sqlserver.sql
-- Tip: selecciona una consulta y presiona F5 para ejecutar solo esa.
-- =====================================================================
-- Azure SQL no permite USE. Antes de ejecutar, elige la base
-- 'sqldb-invacom-fuente' en la lista desplegable de la barra de herramientas.

-- C1. Indicadores generales del periodo
SELECT COUNT(*)                     AS orders,
       COUNT(DISTINCT customerID)  AS active_customers,
       SUM(net)                     AS net_sales,
       SUM(discount_amount)         AS discounts,
       SUM(freight)                 AS freight,
       ROUND(AVG(net), 2)           AS avg_ticket,
       MIN(orderDate)              AS first_order,
       MAX(orderDate)              AS last_order
FROM dbo.v_order_totals;

-- C2. Ventas por año (con número de meses para comparar en igualdad)
SELECT YEAR([month])                        AS [year],
       COUNT(*)                             AS months,
       SUM(net_sales)                       AS net_sales,
       ROUND(SUM(net_sales) / COUNT(*), 2)  AS avg_per_month
FROM dbo.v_monthly_sales
GROUP BY YEAR([month])
ORDER BY [year];

-- C3. Tendencia mensual con crecimiento contra el mes anterior
SELECT [month], orders, net_sales,
       ROUND(100 * (net_sales / NULLIF(LAG(net_sales) OVER (ORDER BY [month]), 0) - 1), 1) AS pct_vs_prev_month,
       incomplete_month
FROM dbo.v_monthly_sales
ORDER BY [month];

-- C4. Top 10 productos y su peso en las ventas
SELECT TOP 10 productName, category, units, net_sales,
       ROUND(100 * net_sales / SUM(net_sales) OVER (), 1) AS pct_of_total
FROM dbo.v_product_performance
ORDER BY net_sales DESC;

-- C5. Clientes que forman el 80% de las ventas (Pareto)
SELECT sales_rank, companyName, country, orders, net_sales, cumulative_pct
FROM dbo.v_customer_summary
WHERE cumulative_pct <= 80 OR sales_rank = 1
ORDER BY sales_rank;

-- C6. Productos descontinuados que siguen vendiéndose
SELECT productName, category, units, net_sales, last_sale
FROM dbo.v_product_performance
WHERE is_discontinued = 1
ORDER BY net_sales DESC;

-- C7. Vendedores: ranking y comparación contra el promedio del equipo
SELECT employeeName, title, manager, orders, net_sales, avg_ticket,
       ROUND(100 * (net_sales / AVG(net_sales) OVER () - 1), 1) AS pct_vs_team_avg
FROM dbo.v_employee_performance
ORDER BY net_sales DESC;

-- C8. Matriz categoría × año
SELECT category,
       SUM(CASE WHEN YEAR(orderDate) = 2013 THEN net END) AS y2013,
       SUM(CASE WHEN YEAR(orderDate) = 2014 THEN net END) AS y2014,
       SUM(CASE WHEN YEAR(orderDate) = 2015 THEN net END) AS y2015
FROM dbo.v_order_lines
GROUP BY category
ORDER BY y2014 DESC;

-- C9. Transportistas comparados
SELECT * FROM dbo.v_shipper_performance ORDER BY avg_days_to_ship;

-- C10. Efecto del aumento de precios de 2014 por producto
SELECT productName, price, current_list_price, pct_of_list, valid_from, valid_to, lines
FROM dbo.v_product_price_history
ORDER BY productName, valid_from;
