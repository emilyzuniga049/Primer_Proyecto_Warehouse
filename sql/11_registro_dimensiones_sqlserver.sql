-- =====================================================================
-- INVACOM DW · REGISTRO DE LA CARGA DE DIMENSIONES (SQL Server / T-SQL)
-- Base: sqldb-invacom-dw   (elegirla en la lista desplegable; Azure SQL no permite USE)
-- Ejecutar el script completo (F5) una vez para crear el procedimiento.
--
-- Crea dbo.usp_registrar_carga_dimensiones. El pipeline pl_carga_dimensiones
-- lo llama al final, cuando las 5 actividades de carga terminaron bien,
-- y deja una fila por dimensión en dbo.etl_log_carga, igual que staging
-- (pl_extraccion_stg) y los hechos (usp_cargar_fact_ventas).
--
--   filas_leidas   = filas de la tabla de staging de origen
--   filas_copiadas = filas de la dimensión, sin contar la fila -1 "Desconocido"
--   estado         = 'Exitoso' si cuadran; 'Revisar' si no
--
-- dim_tiempo no tiene tabla de origen (se genera), así que filas_leidas va en NULL.
-- =====================================================================

CREATE OR ALTER PROCEDURE dbo.usp_registrar_carga_dimensiones
    @id_ejecucion NVARCHAR(100) = NULL,
    @pipeline     NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run NVARCHAR(100) = COALESCE(@id_ejecucion, CONVERT(NVARCHAR(100), NEWID()));
    DECLARE @pl  NVARCHAR(200) = COALESCE(@pipeline, N'ejecucion manual');

    INSERT INTO dbo.etl_log_carga
        (id_ejecucion, pipeline, tabla_origen, tabla_destino, estado, filas_leidas, filas_copiadas)
    SELECT @run, @pl, c.origen, c.destino,
           CASE WHEN c.leidas IS NULL OR c.leidas = c.copiadas THEN N'Exitoso' ELSE N'Revisar' END,
           c.leidas, c.copiadas
    FROM (VALUES
        (N'dbo.stg_shippers',  N'dbo.dim_transportista',
            (SELECT COUNT_BIG(*) FROM dbo.stg_shippers),
            (SELECT COUNT_BIG(*) FROM dbo.dim_transportista WHERE transportista_key <> -1)),
        (N'dbo.stg_customers', N'dbo.dim_cliente',
            (SELECT COUNT_BIG(*) FROM dbo.stg_customers),
            (SELECT COUNT_BIG(*) FROM dbo.dim_cliente WHERE cliente_key <> -1)),
        (N'dbo.stg_products + dbo.stg_categories', N'dbo.dim_producto',
            (SELECT COUNT_BIG(*) FROM dbo.stg_products),
            (SELECT COUNT_BIG(*) FROM dbo.dim_producto WHERE producto_key <> -1)),
        (N'dbo.stg_employees', N'dbo.dim_empleado',
            (SELECT COUNT_BIG(*) FROM dbo.stg_employees),
            (SELECT COUNT_BIG(*) FROM dbo.dim_empleado WHERE empleado_key <> -1)),
        (N'generada (usp_cargar_dim_tiempo)', N'dbo.dim_tiempo',
            NULL,
            (SELECT COUNT_BIG(*) FROM dbo.dim_tiempo WHERE fecha_key <> -1))
    ) AS c (origen, destino, leidas, copiadas);
END;
GO

-- ---------------------------------------------------------------------
-- Prueba manual (opcional). El pipeline hace lo mismo.
-- ---------------------------------------------------------------------
/*
EXEC dbo.usp_registrar_carga_dimensiones;

SELECT TOP 5 tabla_origen, tabla_destino, estado, filas_leidas, filas_copiadas, pipeline, fecha_registro_utc
FROM dbo.etl_log_carga
ORDER BY log_id DESC;
-- Esperado: transportista 3/3, cliente 91/91, producto 77/77, empleado 9/9,
--           tiempo NULL/1095, todas 'Exitoso'
*/
