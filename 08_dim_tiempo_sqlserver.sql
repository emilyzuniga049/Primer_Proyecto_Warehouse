-- =====================================================================
-- INVACOM DW · CARGA DE dim_tiempo (SQL Server / T-SQL)
-- Base: sqldb-invacom-dw   (elegirla en la lista desplegable; Azure SQL no permite USE)
-- Ejecutar el script completo (F5) una vez para crear el procedimiento.
--
-- Crea dbo.usp_cargar_dim_tiempo, que llama el pipeline pl_carga_dimensiones
-- de ADF (actividad "Procedimiento almacenado"). Genera un calendario del
-- 01/01/2013 al 31/12/2015 (1 095 días), que cubre todos los pedidos
-- (jul 2013 a may 2015), con nombres de mes y día en español.
--
-- Es idempotente: solo inserta las fechas que todavía no existen, así que
-- se puede ejecutar varias veces sin duplicar filas. La fila -1
-- "Desconocido" (de 04_creacion_dw_sqlserver.sql) no se toca.
-- =====================================================================

CREATE OR ALTER PROCEDURE dbo.usp_cargar_dim_tiempo
    @fecha_inicio DATE = '2013-01-01',
    @fecha_fin    DATE = '2015-12-31'
AS
BEGIN
    SET NOCOUNT ON;

    WITH numeros AS (
        -- Una fila por cada día del rango (0, 1, 2, ...)
        SELECT TOP (DATEDIFF(DAY, @fecha_inicio, @fecha_fin) + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    ),
    fechas AS (
        SELECT DATEADD(DAY, n, @fecha_inicio) AS fecha
        FROM numeros
    ),
    calendario AS (
        SELECT fecha,
               CONVERT(INT, CONVERT(CHAR(8), fecha, 112)) AS fecha_key,   -- AAAAMMDD
               YEAR(fecha)                                AS anio,
               DATEPART(QUARTER, fecha)                   AS trimestre,
               MONTH(fecha)                               AS mes,
               DAY(fecha)                                 AS dia,
               -- 0 = lunes ... 6 = domingo. Se calcula contra el 01/01/1900
               -- (que fue lunes) para no depender del idioma ni de DATEFIRST.
               DATEDIFF(DAY, CAST('19000101' AS DATE), fecha) % 7 AS dia_semana
        FROM fechas
    )
    INSERT INTO dbo.dim_tiempo
        (fecha_key, fecha, anio, trimestre, mes, nombre_mes, dia, nombre_dia, es_fin_de_semana)
    SELECT c.fecha_key,
           c.fecha,
           c.anio,
           c.trimestre,
           c.mes,
           CHOOSE(c.mes, N'Enero', N'Febrero', N'Marzo', N'Abril', N'Mayo', N'Junio',
                         N'Julio', N'Agosto', N'Septiembre', N'Octubre', N'Noviembre', N'Diciembre'),
           c.dia,
           CHOOSE(c.dia_semana + 1, N'Lunes', N'Martes', N'Miércoles', N'Jueves',
                                    N'Viernes', N'Sábado', N'Domingo'),
           CASE WHEN c.dia_semana IN (5, 6) THEN N'Sí' ELSE N'No' END
    FROM calendario c
    WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_tiempo t WHERE t.fecha_key = c.fecha_key);
END;
GO

-- ---------------------------------------------------------------------
-- Prueba manual (opcional). El pipeline hace lo mismo.
-- ---------------------------------------------------------------------
/*
EXEC dbo.usp_cargar_dim_tiempo;

SELECT COUNT(*) AS filas FROM dbo.dim_tiempo;            -- 1 096 (1 095 días + fila -1)
SELECT * FROM dbo.dim_tiempo WHERE fecha_key = 20130704; -- Jueves, julio, trimestre 3
SELECT anio, COUNT(*) AS dias FROM dbo.dim_tiempo GROUP BY anio ORDER BY anio;
*/
