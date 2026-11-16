-- =====================================================================
-- INVACOM DW · VALIDACIÓN DE LOS DATOS CARGADOS (SQL Server / T-SQL)
-- Base: sqldb-invacom-dw   (elegirla en la lista desplegable; Azure SQL no permite USE)
-- Ejecutar después de correr pl_etl_completo en ADF. Solo lectura: no modifica nada.
--
-- Valida el DW de punta a punta. Complementa a:
--   07_verificacion_staging_sqlserver.sql     (staging)
--   09_verificacion_dimensiones_sqlserver.sql (dimensiones)
--   11_registro_dimensiones_sqlserver.sql     (bitácora de dimensiones)
--
-- Devuelve UNA sola tabla: una fila por revisión, con el valor en el DW,
-- el esperado y el estado OK / REVISAR. Todas deben quedar en OK.
--
-- Bloques:
--   V1 Conteos de todas las capas (staging, dimensiones, hechos)
--   V2 Totales de fact_ventas contra los CSV fuente
--   V3 Reconciliación staging → fact_ventas (recalcula los montos desde staging)
--   V4 Integridad de la tabla de hechos
--   V5 Reglas de negocio y de limpieza
--   V6 Respuestas a las preguntas de negocio de Invacom
--   V7 Bitácora: la última carga de cada una de las 13 tablas quedó en "Exitoso"
--   V8 Comparación fila por fila: las 2 155 líneas, en sus 15 columnas
--
-- Resultado de la ejecución del 15/11/2026: 75 revisiones, todas en OK.
-- Comprobación aparte en sqldb-invacom-fuente (la fuente original):
--   SELECT COUNT(*) AS lineas,
--          SUM(CAST(od.quantity * CAST(od.unitPrice AS DECIMAL(10,2)) AS DECIMAL(12,2))) AS bruto,
--          (SELECT SUM(CAST(freight AS DECIMAL(10,2))) FROM dbo.orders) AS flete
--   FROM dbo.order_details od;
--   → 2155 · 1354458.59 · 64942.69 (igual que staging y los CSV)
--
-- Los valores esperados se calcularon desde los 7 CSV de northwind_traders.zip
-- con el redondeo de SQL Server (medio hacia arriba, 2 decimales). Azure SQL no
-- permite consultas entre bases, por eso la fuente se compara contra staging
-- (copia exacta de sqldb-invacom-fuente) y contra los valores de los CSV.
-- =====================================================================

WITH
-- ---------- V1. Conteos ----------
conteo AS (
    SELECT t.name AS tabla, SUM(p.rows) AS filas
    FROM sys.tables t
    JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
    WHERE t.schema_id = SCHEMA_ID(N'dbo')
    GROUP BY t.name
),
v1 AS (
    SELECT 'V1 Conteos' AS bloque, e.tabla AS revision,
           CAST(c.filas AS DECIMAL(14,2)) AS valor_dw, e.esperado, 0.00 AS tolerancia
    FROM (VALUES
        ('stg_categories',        8.00), ('stg_customers',      91.00), ('stg_employees',       9.00),
        ('stg_orders',          830.00), ('stg_order_details', 2155.00), ('stg_products',       77.00),
        ('stg_shippers',          3.00),
        ('dim_cliente',          92.00), ('dim_producto',       78.00), ('dim_empleado',       10.00),
        ('dim_transportista',     4.00), ('dim_tiempo',       1096.00),
        ('fact_ventas',        2155.00)
    ) e(tabla, esperado)
    LEFT JOIN conteo c ON c.tabla = e.tabla
),

-- ---------- V2. Totales contra los CSV ----------
tot AS (
    SELECT COUNT(DISTINCT pedido_id) AS pedidos, SUM(cantidad) AS cantidad,
           SUM(monto_bruto) AS bruto, SUM(monto_descuento) AS descuento,
           SUM(monto_neto) AS neto, SUM(flete_prorrateado) AS flete
    FROM dbo.fact_ventas
),
v2 AS (
    SELECT 'V2 Totales vs CSV' AS bloque, x.revision, x.valor_dw, x.esperado, 0.00 AS tolerancia
    FROM tot CROSS APPLY (VALUES
        ('Pedidos distintos', CAST(tot.pedidos  AS DECIMAL(14,2)),     830.00),
        ('Cantidad vendida',  CAST(tot.cantidad AS DECIMAL(14,2)),   51317.00),
        ('Monto bruto',       CAST(tot.bruto     AS DECIMAL(14,2)), 1354458.59),
        ('Monto descuento',   CAST(tot.descuento AS DECIMAL(14,2)),   88665.83),
        ('Monto neto',        CAST(tot.neto      AS DECIMAL(14,2)), 1265792.76),
        ('Flete prorrateado', CAST(tot.flete     AS DECIMAL(14,2)),   64942.70)
    ) x(revision, valor_dw, esperado)
),

-- ---------- V3. Reconciliación staging → fact_ventas ----------
stg AS (
    SELECT COUNT(*) AS lineas,
           SUM(CAST(CAST(od.quantity AS INT) * CAST(od.unitPrice AS DECIMAL(10,2)) AS DECIMAL(12,2))) AS bruto,
           SUM(CAST(CAST(od.quantity AS INT) * CAST(od.unitPrice AS DECIMAL(10,2))
                    * CAST(od.discount AS DECIMAL(4,2)) AS DECIMAL(12,2)))                          AS descuento
    FROM dbo.stg_order_details od
    JOIN dbo.stg_orders o ON o.orderID = od.orderID
),
flete_stg AS (
    SELECT SUM(CAST(freight AS DECIMAL(10,2))) AS flete FROM dbo.stg_orders
),
fct AS (
    SELECT COUNT(*) AS lineas, SUM(monto_bruto) AS bruto, SUM(monto_descuento) AS descuento,
           SUM(flete_prorrateado) AS flete
    FROM dbo.fact_ventas
),
v3 AS (
    SELECT 'V3 Staging vs fact' AS bloque, x.revision, x.valor_dw, x.esperado, x.tolerancia
    FROM stg CROSS JOIN flete_stg CROSS JOIN fct
    CROSS APPLY (VALUES
        ('Líneas (fact vs staging)',           CAST(fct.lineas AS DECIMAL(14,2)), CAST(stg.lineas AS DECIMAL(14,2)), 0.00),
        ('Monto bruto (fact vs staging)',      CAST(fct.bruto AS DECIMAL(14,2)),     CAST(stg.bruto AS DECIMAL(14,2)),     0.00),
        ('Monto descuento (fact vs staging)',  CAST(fct.descuento AS DECIMAL(14,2)), CAST(stg.descuento AS DECIMAL(14,2)), 0.00),
        ('Flete (fact vs staging, ±0.05)',     CAST(fct.flete AS DECIMAL(14,2)),     CAST(flete_stg.flete AS DECIMAL(14,2)), 0.05)
    ) x(revision, valor_dw, esperado, tolerancia)
),

-- ---------- V4. Integridad de la tabla de hechos ----------
v4 AS (
    SELECT 'V4 Integridad' AS bloque, x.revision, CAST(x.casos AS DECIMAL(14,2)) AS valor_dw,
           0.00 AS esperado, 0.00 AS tolerancia
    FROM (
        SELECT 'Líneas duplicadas (pedido + producto)' AS revision,
               (SELECT COUNT(*) FROM (SELECT pedido_id, producto_key FROM dbo.fact_ventas
                                      GROUP BY pedido_id, producto_key HAVING COUNT(*) > 1) d) AS casos
        UNION ALL
        SELECT 'Filas en "Desconocido" (-1)',
               (SELECT COUNT(*) FROM dbo.fact_ventas
                WHERE fecha_key = -1 OR cliente_key = -1 OR producto_key = -1
                   OR empleado_key = -1 OR transportista_key = -1)
        UNION ALL
        SELECT 'Llaves sin fila en su dimensión',
               (SELECT COUNT(*) FROM dbo.fact_ventas f
                LEFT JOIN dbo.dim_tiempo        t ON t.fecha_key         = f.fecha_key
                LEFT JOIN dbo.dim_cliente       c ON c.cliente_key       = f.cliente_key
                LEFT JOIN dbo.dim_producto      p ON p.producto_key      = f.producto_key
                LEFT JOIN dbo.dim_empleado      e ON e.empleado_key      = f.empleado_key
                LEFT JOIN dbo.dim_transportista s ON s.transportista_key = f.transportista_key
                WHERE t.fecha_key IS NULL OR c.cliente_key IS NULL OR p.producto_key IS NULL
                   OR e.empleado_key IS NULL OR s.transportista_key IS NULL)
        UNION ALL
        SELECT 'Líneas de staging que no llegaron a fact',
               (SELECT COUNT(*) FROM dbo.stg_order_details od
                WHERE NOT EXISTS (SELECT 1 FROM dbo.fact_ventas f
                                  JOIN dbo.dim_producto p ON p.producto_key = f.producto_key
                                  WHERE f.pedido_id = od.orderID AND p.producto_id = od.productID))
        UNION ALL
        SELECT 'Pedidos con fecha distinta a staging',
               (SELECT COUNT(*) FROM (SELECT DISTINCT f.pedido_id, t.fecha
                                      FROM dbo.fact_ventas f JOIN dbo.dim_tiempo t ON t.fecha_key = f.fecha_key) x
                JOIN dbo.stg_orders o ON o.orderID = x.pedido_id
                WHERE x.fecha <> TRY_CAST(o.orderDate AS DATE))
        UNION ALL
        SELECT 'Pedidos con cliente distinto a staging',
               (SELECT COUNT(*) FROM (SELECT DISTINCT f.pedido_id, c.cliente_id
                                      FROM dbo.fact_ventas f JOIN dbo.dim_cliente c ON c.cliente_key = f.cliente_key) x
                JOIN dbo.stg_orders o ON o.orderID = x.pedido_id
                WHERE x.cliente_id <> TRIM(o.customerID))
    ) x
),

-- ---------- V5. Reglas de negocio y de limpieza ----------
v5 AS (
    SELECT 'V5 Reglas' AS bloque, x.revision, CAST(x.casos AS DECIMAL(14,2)) AS valor_dw,
           x.esperado, 0.00 AS tolerancia
    FROM (
        SELECT 'monto_neto <> bruto - descuento' AS revision,
               (SELECT COUNT(*) FROM dbo.fact_ventas WHERE monto_neto <> monto_bruto - monto_descuento) AS casos,
               0.00 AS esperado
        UNION ALL
        SELECT 'monto_bruto <> cantidad x precio',
               (SELECT COUNT(*) FROM dbo.fact_ventas
                WHERE monto_bruto <> CAST(cantidad * precio_unitario AS DECIMAL(12,2))), 0.00
        UNION ALL
        SELECT 'Descuento fuera de 0 a 0.25',
               (SELECT COUNT(*) FROM dbo.fact_ventas WHERE descuento < 0 OR descuento > 0.25), 0.00
        UNION ALL
        SELECT 'Cantidad o precio <= 0',
               (SELECT COUNT(*) FROM dbo.fact_ventas WHERE cantidad <= 0 OR precio_unitario <= 0), 0.00
        UNION ALL
        SELECT 'Líneas no enviadas (enviado = No)',
               (SELECT COUNT(*) FROM dbo.fact_ventas WHERE enviado = N'No'), 73.00
        UNION ALL
        SELECT 'Pedidos no enviados',
               (SELECT COUNT(DISTINCT pedido_id) FROM dbo.fact_ventas WHERE enviado = N'No'), 21.00
        UNION ALL
        SELECT 'enviado y dias_entrega incoherentes',
               (SELECT COUNT(*) FROM dbo.fact_ventas
                WHERE (enviado = N'No' AND dias_entrega IS NOT NULL)
                   OR (enviado <> N'No' AND dias_entrega IS NULL)), 0.00
        UNION ALL
        SELECT 'dias_entrega fuera de 1 a 37',
               (SELECT COUNT(*) FROM dbo.fact_ventas WHERE dias_entrega < 1 OR dias_entrega > 37), 0.00
        UNION ALL
        SELECT 'Pedidos cuyo flete repartido no suma el original (±0.02)',
               (SELECT COUNT(*) FROM (SELECT pedido_id, SUM(flete_prorrateado) AS repartido
                                      FROM dbo.fact_ventas GROUP BY pedido_id) r
                JOIN dbo.stg_orders o ON o.orderID = r.pedido_id
                WHERE ABS(r.repartido - CAST(o.freight AS DECIMAL(10,2))) > 0.02), 0.00
        UNION ALL
        SELECT 'Clientes distintos con compras',
               (SELECT COUNT(DISTINCT cliente_key) FROM dbo.fact_ventas), 89.00
        UNION ALL
        SELECT 'Productos distintos vendidos',
               (SELECT COUNT(DISTINCT producto_key) FROM dbo.fact_ventas), 77.00
    ) x
),

-- ---------- V6. Preguntas de negocio ----------
negocio AS (
    SELECT 'Trimestre' AS pregunta, CONCAT(t.anio, '-T', t.trimestre) AS valor, SUM(f.monto_neto) AS resultado
    FROM dbo.fact_ventas f JOIN dbo.dim_tiempo t ON t.fecha_key = f.fecha_key
    GROUP BY t.anio, t.trimestre
    UNION ALL
    SELECT 'País', c.pais, SUM(f.monto_neto)
    FROM dbo.fact_ventas f JOIN dbo.dim_cliente c ON c.cliente_key = f.cliente_key GROUP BY c.pais
    UNION ALL
    SELECT 'Categoría', p.categoria, SUM(f.monto_neto)
    FROM dbo.fact_ventas f JOIN dbo.dim_producto p ON p.producto_key = f.producto_key GROUP BY p.categoria
    UNION ALL
    SELECT 'Empleado', e.nombre, SUM(f.monto_neto)
    FROM dbo.fact_ventas f JOIN dbo.dim_empleado e ON e.empleado_key = f.empleado_key GROUP BY e.nombre
    UNION ALL
    SELECT 'Transportista', s.transportista, CAST(COUNT(DISTINCT f.pedido_id) AS DECIMAL(14,2))
    FROM dbo.fact_ventas f JOIN dbo.dim_transportista s ON s.transportista_key = f.transportista_key
    GROUP BY s.transportista
),
v6 AS (
    SELECT 'V6 Negocio' AS bloque, CONCAT(e.pregunta, ': ', e.valor) AS revision,
           CAST(n.resultado AS DECIMAL(14,2)) AS valor_dw, e.esperado, 0.00 AS tolerancia
    FROM (VALUES
        ('Trimestre',     '2013-T3',           79728.56),
        ('Trimestre',     '2013-T4',          128355.39),
        ('Trimestre',     '2014-T1',          138288.90),
        ('Trimestre',     '2014-T2',          143177.02),
        ('Trimestre',     '2014-T3',          153937.71),
        ('Trimestre',     '2014-T4',          181681.42),
        ('Trimestre',     '2015-T1',          298491.49),
        ('Trimestre',     '2015-T2',          142132.27),
        ('País',          'USA',              245584.56),
        ('País',          'Germany',          230284.57),
        ('País',          'Austria',          128003.83),
        ('Categoría',     'Beverages',        267868.16),
        ('Categoría',     'Dairy Products',   234507.25),
        ('Categoría',     'Confections',      167357.13),
        ('Empleado',      'Margaret Peacock', 232890.82),
        ('Empleado',      'Janet Leverling',  202812.79),
        ('Empleado',      'Nancy Davolio',    192107.52),
        ('Transportista', 'United Package',      326.00),
        ('Transportista', 'Federal Shipping',    255.00),
        ('Transportista', 'Speedy Express',      249.00)
    ) e(pregunta, valor, esperado)
    LEFT JOIN negocio n ON n.pregunta = e.pregunta AND n.valor = e.valor
),

-- ---------- V7. Bitácora: última carga de cada tabla ----------
ultima AS (
    SELECT tabla_destino, estado,
           ROW_NUMBER() OVER (PARTITION BY tabla_destino
                              ORDER BY fecha_registro_utc DESC, log_id DESC) AS rn
    FROM dbo.etl_log_carga
),
v7 AS (
    SELECT 'V7 Bitácora' AS bloque, CONCAT('Última carga exitosa: ', e.destino) AS revision,
           CAST(CASE WHEN u.estado = N'Exitoso' THEN 1 WHEN u.estado IS NULL THEN NULL ELSE 0 END
                AS DECIMAL(14,2)) AS valor_dw,
           1.00 AS esperado, 0.00 AS tolerancia
    FROM (VALUES
        (N'dbo.stg_categories'), (N'dbo.stg_customers'), (N'dbo.stg_employees'), (N'dbo.stg_orders'),
        (N'dbo.stg_order_details'), (N'dbo.stg_products'), (N'dbo.stg_shippers'),
        (N'dbo.dim_cliente'), (N'dbo.dim_producto'), (N'dbo.dim_empleado'),
        (N'dbo.dim_transportista'), (N'dbo.dim_tiempo'),
        (N'dbo.fact_ventas')
    ) e(destino)
    LEFT JOIN ultima u ON u.tabla_destino = e.destino AND u.rn = 1
),

-- ---------- V8. Comparación fila por fila (staging recalculado vs fact_ventas) ----------
-- Recalcula cada una de las 2 155 líneas desde staging, con las mismas reglas
-- de usp_cargar_fact_ventas, y la compara con fact_ventas en sus 15 columnas
-- (llaves resueltas a sus códigos originales). Cualquier línea que falte, sobre
-- o difiera en un solo valor aparece como diferencia. Esperado: 0.
lin_base AS (
    SELECT o.orderID AS pedido_id, od.productID AS producto_id, TRIM(o.customerID) AS cliente_id,
           o.employeeID AS empleado_id, o.shipperID AS transportista_id,
           TRY_CAST(o.orderDate AS DATE) AS fecha,
           CAST(od.quantity AS INT) AS cantidad,
           CAST(od.unitPrice AS DECIMAL(10,2)) AS precio_unitario,
           CAST(od.discount AS DECIMAL(4,2)) AS descuento,
           CAST(od.quantity * CAST(od.unitPrice AS DECIMAL(10,2)) AS DECIMAL(12,2)) AS monto_bruto,
           CAST(od.quantity * CAST(od.unitPrice AS DECIMAL(10,2))
                * CAST(od.discount AS DECIMAL(4,2)) AS DECIMAL(12,2)) AS monto_descuento,
           CAST(o.freight AS DECIMAL(10,2)) AS flete,
           SUM(od.quantity * CAST(od.unitPrice AS DECIMAL(10,2))) OVER (PARTITION BY o.orderID) AS bruto_pedido,
           DATEDIFF(DAY, TRY_CAST(o.orderDate AS DATE), TRY_CAST(o.shippedDate AS DATE)) AS dias_entrega,
           CASE WHEN o.shippedDate IS NULL THEN N'No' ELSE N'Sí' END AS enviado
    FROM dbo.stg_order_details od JOIN dbo.stg_orders o ON o.orderID = od.orderID
),
lin_esperada AS (
    SELECT pedido_id, producto_id, cliente_id, empleado_id, transportista_id, fecha, cantidad,
           precio_unitario, descuento, monto_bruto, monto_descuento,
           monto_bruto - monto_descuento AS monto_neto,
           CAST(flete * monto_bruto / NULLIF(bruto_pedido, 0) AS DECIMAL(10,2)) AS flete_prorrateado,
           dias_entrega, enviado
    FROM lin_base
),
lin_dw AS (
    SELECT f.pedido_id, p.producto_id, c.cliente_id, e.empleado_id, s.transportista_id, t.fecha,
           f.cantidad, f.precio_unitario, f.descuento, f.monto_bruto, f.monto_descuento, f.monto_neto,
           f.flete_prorrateado, f.dias_entrega, f.enviado
    FROM dbo.fact_ventas f
    JOIN dbo.dim_producto p      ON p.producto_key = f.producto_key
    JOIN dbo.dim_cliente c       ON c.cliente_key = f.cliente_key
    JOIN dbo.dim_empleado e      ON e.empleado_key = f.empleado_key
    JOIN dbo.dim_transportista s ON s.transportista_key = f.transportista_key
    JOIN dbo.dim_tiempo t        ON t.fecha_key = f.fecha_key
),
v8 AS (
    SELECT 'V8 Fila por fila' AS bloque, x.revision, CAST(x.casos AS DECIMAL(14,2)) AS valor_dw,
           0.00 AS esperado, 0.00 AS tolerancia
    FROM (
        SELECT 'Líneas que faltan o difieren en fact_ventas' AS revision,
               (SELECT COUNT(*) FROM (SELECT * FROM lin_esperada EXCEPT SELECT * FROM lin_dw) a) AS casos
        UNION ALL
        SELECT 'Líneas que sobran o difieren en fact_ventas',
               (SELECT COUNT(*) FROM (SELECT * FROM lin_dw EXCEPT SELECT * FROM lin_esperada) b)
    ) x
),

todo AS (
    SELECT * FROM v1 UNION ALL SELECT * FROM v2 UNION ALL SELECT * FROM v3
    UNION ALL SELECT * FROM v4 UNION ALL SELECT * FROM v5 UNION ALL SELECT * FROM v6
    UNION ALL SELECT * FROM v7 UNION ALL SELECT * FROM v8
)
SELECT bloque, revision, valor_dw, esperado,
       CASE WHEN valor_dw IS NOT NULL AND ABS(valor_dw - esperado) <= tolerancia
            THEN 'OK' ELSE 'REVISAR' END AS estado
FROM todo
ORDER BY bloque;
