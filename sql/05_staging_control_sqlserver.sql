-- =====================================================================
-- INVACOM DW · CONTROL DE LA EXTRACCIÓN A STAGING (SQL Server / T-SQL)
-- Base: sqldb-invacom-dw   (elegirla en la lista desplegable; Azure SQL no permite USE)
-- Ejecutar el script completo (F5).
--
-- Crea:
--   dbo.etl_log_carga        → bitácora: una fila por tabla copiada en cada ejecución
--   dbo.usp_registrar_carga  → procedimiento que llama el pipeline pl_extraccion_stg de ADF
--
-- Las tablas dbo.stg_<tabla> NO se crean aquí: la Copy Activity de ADF las crea
-- automáticamente (tableOption = autoCreate) con los mismos tipos de la fuente,
-- y en cada ejecución las vacía (TRUNCATE) y las vuelve a llenar.
-- =====================================================================

-- 1. Bitácora de cargas
IF OBJECT_ID(N'dbo.etl_log_carga', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.etl_log_carga (
        log_id              INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_etl_log_carga PRIMARY KEY,
        id_ejecucion        NVARCHAR(100)  NOT NULL,   -- RunId del pipeline en ADF
        pipeline            NVARCHAR(200)  NULL,
        tabla_origen        NVARCHAR(256)  NOT NULL,   -- ej. dbo.orders  (sqldb-invacom-fuente)
        tabla_destino       NVARCHAR(256)  NOT NULL,   -- ej. dbo.stg_orders (sqldb-invacom-dw)
        estado              NVARCHAR(20)   NOT NULL,   -- Exitoso / Fallido
        filas_leidas        BIGINT         NULL,
        filas_copiadas      BIGINT         NULL,
        duracion_seg        INT            NULL,
        mensaje_error       NVARCHAR(MAX)  NULL,
        fecha_registro_utc  DATETIME2(0)   NOT NULL CONSTRAINT df_etl_log_carga_fecha DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX ix_etl_log_carga_ejecucion ON dbo.etl_log_carga (id_ejecucion);
END;
GO

-- 2. Procedimiento que ADF ejecuta después de cada copia
CREATE OR ALTER PROCEDURE dbo.usp_registrar_carga
    @id_ejecucion   NVARCHAR(100),
    @pipeline       NVARCHAR(200),
    @tabla_origen   NVARCHAR(256),
    @tabla_destino  NVARCHAR(256),
    @estado         NVARCHAR(20),
    @filas_leidas   BIGINT        = NULL,
    @filas_copiadas BIGINT        = NULL,
    @duracion_seg   INT           = NULL,
    @mensaje_error  NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.etl_log_carga
        (id_ejecucion, pipeline, tabla_origen, tabla_destino, estado,
         filas_leidas, filas_copiadas, duracion_seg, mensaje_error)
    VALUES
        (@id_ejecucion, @pipeline, @tabla_origen, @tabla_destino, @estado,
         @filas_leidas, @filas_copiadas, @duracion_seg, @mensaje_error);
END;
GO

-- 3. (OPCIONAL) Reiniciar staging
-- autoCreate no modifica una tabla stg_ que ya existe. Si cambian el tipo de
-- una columna en la fuente, borren las tablas stg_ con este bloque y vuelvan a
-- correr el pipeline para que las cree con la estructura nueva.
-- Solo borra tablas que empiezan con stg_; no toca dim_* ni fact_ventas.
/*
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'DROP TABLE dbo.' + QUOTENAME(name) + N';' + CHAR(10)
FROM sys.tables
WHERE schema_id = SCHEMA_ID(N'dbo') AND name LIKE N'stg\_%' ESCAPE N'\';
PRINT @sql;
EXEC sp_executesql @sql;
*/
