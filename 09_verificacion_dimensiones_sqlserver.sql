-- =====================================================================
-- INVACOM DW · VERIFICACIÓN DE LAS DIMENSIONES (SQL Server / T-SQL)
-- Base: sqldb-invacom-dw   (elegirla en la lista desplegable; Azure SQL no permite USE)
-- Ejecutar después de correr el pipeline pl_carga_dimensiones en ADF.
-- Cada consulta muestra lo esperado y un estado OK / REVISAR.
-- Los valores esperados salen del perfilado de la base fuente.
-- =====================================================================

-- D1. Filas por dimensión (incluye la fila -1 "Desconocido")
WITH esperado AS (
    SELECT * FROM (VALUES
        ('dim_cliente',          92),
        ('dim_producto',         78),
        ('dim_empleado',         10),
        ('dim_transportista',     4),
        ('dim_tiempo',         1096)
    ) v(tabla, filas_esperadas)
), real AS (
    SELECT 'dim_cliente'       AS tabla, COUNT(*) AS filas FROM dbo.dim_cliente       UNION ALL
    SELECT 'dim_producto',               COUNT(*)          FROM dbo.dim_producto      UNION ALL
    SELECT 'dim_empleado',               COUNT(*)          FROM dbo.dim_empleado      UNION ALL
    SELECT 'dim_transportista',          COUNT(*)          FROM dbo.dim_transportista UNION ALL
    SELECT 'dim_tiempo',                 COUNT(*)          FROM dbo.dim_tiempo
)
SELECT e.tabla, e.filas_esperadas, r.filas AS filas_reales,
       CASE WHEN r.filas = e.filas_esperadas THEN 'OK' ELSE 'REVISAR' END AS estado
FROM esperado e JOIN real r ON r.tabla = e.tabla
ORDER BY e.tabla;

-- D2. Cada dimensión conserva su fila -1 "Desconocido"
SELECT 'dim_cliente' AS tabla,
       CASE WHEN EXISTS (SELECT 1 FROM dbo.dim_cliente WHERE cliente_key = -1) THEN 'OK' ELSE 'FALTA' END AS fila_desconocido
UNION ALL SELECT 'dim_producto',
       CASE WHEN EXISTS (SELECT 1 FROM dbo.dim_producto WHERE producto_key = -1) THEN 'OK' ELSE 'FALTA' END
UNION ALL SELECT 'dim_empleado',
       CASE WHEN EXISTS (SELECT 1 FROM dbo.dim_empleado WHERE empleado_key = -1) THEN 'OK' ELSE 'FALTA' END
UNION ALL SELECT 'dim_transportista',
       CASE WHEN EXISTS (SELECT 1 FROM dbo.dim_transportista WHERE transportista_key = -1) THEN 'OK' ELSE 'FALTA' END
UNION ALL SELECT 'dim_tiempo',
       CASE WHEN EXISTS (SELECT 1 FROM dbo.dim_tiempo WHERE fecha_key = -1) THEN 'OK' ELSE 'FALTA' END;

-- D3. Sin llaves originales duplicadas (el upsert no debe duplicar)
SELECT 'dim_cliente' AS tabla, COUNT(*) - COUNT(DISTINCT cliente_id) AS duplicados FROM dbo.dim_cliente
UNION ALL SELECT 'dim_producto',      COUNT(*) - COUNT(DISTINCT producto_id)      FROM dbo.dim_producto
UNION ALL SELECT 'dim_empleado',      COUNT(*) - COUNT(DISTINCT empleado_id)      FROM dbo.dim_empleado
UNION ALL SELECT 'dim_transportista', COUNT(*) - COUNT(DISTINCT transportista_id) FROM dbo.dim_transportista
UNION ALL SELECT 'dim_tiempo',        COUNT(*) - COUNT(DISTINCT fecha)            FROM dbo.dim_tiempo;

-- D4. Reglas de limpieza (Tabla 2 del documento). Todas deben dar 0.
SELECT 'Espacios dobles en clientes' AS regla, COUNT(*) AS casos
FROM dbo.dim_cliente
WHERE empresa LIKE '%  %' OR contacto LIKE '%  %' OR cargo_contacto LIKE '%  %' OR ciudad LIKE '%  %'
UNION ALL
SELECT 'Espacios dobles o invisibles en productos', COUNT(*)
FROM dbo.dim_producto
WHERE producto LIKE '%  %' OR cantidad_por_unidad LIKE '%  %'
   OR producto LIKE N'%' + NCHAR(160) + N'%' OR cantidad_por_unidad LIKE N'%' + NCHAR(160) + N'%'
UNION ALL
SELECT 'Clientes sin región', COUNT(*)
FROM dbo.dim_cliente WHERE cliente_key <> -1 AND region IS NULL
UNION ALL
SELECT 'Productos con descontinuado distinto de Sí/No', COUNT(*)
FROM dbo.dim_producto WHERE producto_key <> -1 AND descontinuado NOT IN (N'Sí', N'No')
UNION ALL
SELECT 'Productos sin categoría', COUNT(*)
FROM dbo.dim_producto WHERE producto_key <> -1 AND categoria = N'Sin categoría'
UNION ALL
SELECT 'Empleados sin supervisor (esperado: 1, el vicepresidente)', COUNT(*)
FROM dbo.dim_empleado WHERE supervisor = N'Sin supervisor';

-- D5. Distribuciones para el informe
SELECT region, COUNT(*) AS clientes            -- Europa 54, Latinoamérica 21, Norteamérica 16
FROM dbo.dim_cliente WHERE cliente_key <> -1 GROUP BY region ORDER BY region;

SELECT categoria, COUNT(*) AS productos,       -- 8 categorías
       SUM(CASE WHEN descontinuado = N'Sí' THEN 1 ELSE 0 END) AS descontinuados
FROM dbo.dim_producto WHERE producto_key <> -1 GROUP BY categoria ORDER BY productos DESC;

SELECT supervisor, COUNT(*) AS empleados       -- Andrew Fuller 2, Laura Callahan 3, Steven Buchanan 3, Sin supervisor 1
FROM dbo.dim_empleado WHERE empleado_key <> -1 GROUP BY supervisor ORDER BY supervisor;

SELECT anio, COUNT(*) AS dias,                 -- 365 por año
       SUM(CASE WHEN es_fin_de_semana = N'Sí' THEN 1 ELSE 0 END) AS fines_de_semana
FROM dbo.dim_tiempo WHERE fecha_key <> -1 GROUP BY anio ORDER BY anio;

-- D6. Cobertura: todas las llaves que usará fact_ventas existen en las dimensiones
SELECT 'Clientes de pedidos sin dimensión' AS revision, COUNT(*) AS casos
FROM (SELECT DISTINCT customerID FROM dbo.stg_orders) o
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_cliente d WHERE d.cliente_id = o.customerID)
UNION ALL
SELECT 'Productos de líneas sin dimensión', COUNT(*)
FROM (SELECT DISTINCT productID FROM dbo.stg_order_details) l
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_producto d WHERE d.producto_id = l.productID)
UNION ALL
SELECT 'Empleados de pedidos sin dimensión', COUNT(*)
FROM (SELECT DISTINCT employeeID FROM dbo.stg_orders) o
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_empleado d WHERE d.empleado_id = o.employeeID)
UNION ALL
SELECT 'Transportistas de pedidos sin dimensión', COUNT(*)
FROM (SELECT DISTINCT shipperID FROM dbo.stg_orders) o
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_transportista d WHERE d.transportista_id = o.shipperID)
UNION ALL
SELECT 'Fechas de pedido fuera de dim_tiempo', COUNT(*)
FROM (SELECT DISTINCT orderDate FROM dbo.stg_orders) o
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_tiempo d WHERE d.fecha = o.orderDate);
