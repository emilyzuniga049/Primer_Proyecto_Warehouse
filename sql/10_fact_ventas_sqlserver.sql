-- =====================================================================
-- INVACOM DW · CARGA DE fact_ventas (SQL Server / T-SQL)
-- Base: sqldb-invacom-dw
-- Crea dbo.usp_cargar_fact_ventas, que ejecuta el pipeline de hechos.
-- Recarga completa: vacía fact_ventas y la vuelve a llenar desde staging,
-- dentro de una transacción (si algo falla, no queda a medias).
-- Registra cada ejecución en dbo.etl_log_carga.
-- =====================================================================

CREATE OR ALTER PROCEDURE dbo.usp_cargar_fact_ventas
    @id_ejecucion NVARCHAR(100) = NULL,
    @pipeline     NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @inicio   DATETIME2(0)  = SYSUTCDATETIME();
    DECLARE @run      NVARCHAR(100) = COALESCE(@id_ejecucion, CONVERT(NVARCHAR(100), NEWID()));
    DECLARE @pl       NVARCHAR(200) = COALESCE(@pipeline, N'ejecucion manual');
    DECLARE @origen   NVARCHAR(256) = N'dbo.stg_orders + dbo.stg_order_details';
    DECLARE @destino  NVARCHAR(256) = N'dbo.fact_ventas';
    DECLARE @leidas   BIGINT;
    DECLARE @cargadas BIGINT;
    DECLARE @duracion INT;
    DECLARE @error    NVARCHAR(MAX);

    SELECT @leidas = COUNT(*) FROM dbo.stg_order_details;

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE dbo.fact_ventas;

        WITH lineas AS (
            SELECT o.orderID                            pedido_id,
                   TRIM(o.customerID)                   cliente_id,
                   o.employeeID                         empleado_id,
                   o.shipperID                          transportista_id,
                   TRY_CAST(o.orderDate   AS DATE)      fecha_pedido,
                   TRY_CAST(o.shippedDate AS DATE)      fecha_envio,
                   CAST(o.freight     AS DECIMAL(10,2)) flete,
                   od.productID                         producto_id,
                   CAST(od.quantity   AS INT)           cantidad,
                   CAST(od.unitPrice  AS DECIMAL(10,2)) precio_unitario,
                   CAST(od.discount   AS DECIMAL(4,2))  descuento
            FROM dbo.stg_order_details od
            JOIN dbo.stg_orders o ON o.orderID = od.orderID
        ),
        montos AS (
            SELECT l.*,
                   CAST(l.cantidad * l.precio_unitario AS DECIMAL(12,2))                 monto_bruto,
                   CAST(l.cantidad * l.precio_unitario * l.descuento AS DECIMAL(12,2))   monto_descuento,
                   SUM(l.cantidad * l.precio_unitario) OVER (PARTITION BY l.pedido_id)   bruto_pedido
            FROM lineas l
        )
        INSERT INTO dbo.fact_ventas
            (fecha_key, cliente_key, producto_key, empleado_key, transportista_key,
             pedido_id, cantidad, precio_unitario, descuento,
             monto_bruto, monto_descuento, monto_neto,
             flete_prorrateado, dias_entrega, enviado)
        SELECT COALESCE(t.fecha_key, -1),
               COALESCE(c.cliente_key, -1),
               COALESCE(p.producto_key, -1),
               COALESCE(e.empleado_key, -1),
               COALESCE(s.transportista_key, -1),
               m.pedido_id,
               m.cantidad,
               m.precio_unitario,
               m.descuento,
               m.monto_bruto,
               m.monto_descuento,
               m.monto_bruto - m.monto_descuento,
               CAST(m.flete * m.monto_bruto / NULLIF(m.bruto_pedido, 0) AS DECIMAL(10,2)),
               DATEDIFF(DAY, m.fecha_pedido, m.fecha_envio),
               CASE WHEN m.fecha_envio IS NULL THEN N'No' ELSE N'Sí' END
        FROM montos m
        LEFT JOIN dbo.dim_tiempo        t ON t.fecha            = m.fecha_pedido
        LEFT JOIN dbo.dim_cliente       c ON c.cliente_id       = m.cliente_id
        LEFT JOIN dbo.dim_producto      p ON p.producto_id      = m.producto_id
        LEFT JOIN dbo.dim_empleado      e ON e.empleado_id      = m.empleado_id
        LEFT JOIN dbo.dim_transportista s ON s.transportista_id = m.transportista_id;

        SET @cargadas = @@ROWCOUNT;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        SET @error    = ERROR_MESSAGE();
        SET @duracion = DATEDIFF(SECOND, @inicio, SYSUTCDATETIME());

        EXEC dbo.usp_registrar_carga
             @id_ejecucion = @run, @pipeline = @pl,
             @tabla_origen = @origen, @tabla_destino = @destino,
             @estado = N'Fallido', @filas_leidas = @leidas,
             @duracion_seg = @duracion, @mensaje_error = @error;

        THROW;
    END CATCH;

    SET @duracion = DATEDIFF(SECOND, @inicio, SYSUTCDATETIME());

    EXEC dbo.usp_registrar_carga
         @id_ejecucion = @run, @pipeline = @pl,
         @tabla_origen = @origen, @tabla_destino = @destino,
         @estado = N'Exitoso', @filas_leidas = @leidas,
         @filas_copiadas = @cargadas, @duracion_seg = @duracion;
END;
GO
