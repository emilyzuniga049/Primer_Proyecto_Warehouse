-- =====================================================================
-- INVACOM DW · VERIFICACIÓN DE LA EXTRACCIÓN A STAGING (SQL Server / T-SQL)
-- Ejecutar después de correr pl_extraccion_stg en ADF.
-- Los resultados sirven como evidencia para el informe y la sustentación.
-- =====================================================================


-- =====================================================================
-- PARTE A · Base: sqldb-invacom-dw
-- =====================================================================

-- S1. Resultado de la última ejecución: cuadre filas leídas vs. copiadas
WITH ultima AS (
    SELECT TOP 1 id_ejecucion
    FROM dbo.etl_log_carga
    ORDER BY fecha_registro_utc DESC
)
SELECT l.tabla_origen, l.tabla_destino, l.estado,
       l.filas_leidas, l.filas_copiadas,
       CASE WHEN l.filas_leidas = l.filas_copiadas THEN 'OK' ELSE 'REVISAR' END AS cuadre,
       l.duracion_seg, l.mensaje_error, l.fecha_registro_utc
FROM dbo.etl_log_carga l
JOIN ultima u ON u.id_ejecucion = l.id_ejecucion
ORDER BY l.tabla_origen;

-- S2. Historial: una fila por ejecución del pipeline
SELECT id_ejecucion,
       MIN(fecha_registro_utc)                              AS inicio_utc,
       COUNT(*)                                             AS tablas,
       SUM(CASE WHEN estado = 'Exitoso' THEN 1 ELSE 0 END)  AS exitosas,
       SUM(CASE WHEN estado = 'Fallido' THEN 1 ELSE 0 END)  AS fallidas,
       SUM(filas_copiadas)                                  AS filas_totales
FROM dbo.etl_log_carga
GROUP BY id_ejecucion
ORDER BY inicio_utc DESC;

-- S3. Conteo contra lo esperado según docs/modelo-dimensional.md
WITH esperado AS (
    SELECT * FROM (VALUES
        ('stg_categories',      8),
        ('stg_customers',      91),
        ('stg_employees',       9),
        ('stg_orders',        830),
        ('stg_order_details', 2155),
        ('stg_products',       77),
        ('stg_shippers',        3)
    ) v(tabla, filas_esperadas)
), real AS (
    SELECT t.name AS tabla, SUM(p.rows) AS filas
    FROM sys.tables t
    JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
    WHERE t.schema_id = SCHEMA_ID(N'dbo') AND t.name LIKE N'stg\_%' ESCAPE N'\'
    GROUP BY t.name
)
SELECT e.tabla, e.filas_esperadas, r.filas AS filas_en_stg,
       CASE WHEN r.filas = e.filas_esperadas THEN 'OK'
            WHEN r.filas IS NULL THEN 'NO EXISTE'
            ELSE 'REVISAR' END AS estado
FROM esperado e
LEFT JOIN real r ON r.tabla = e.tabla
ORDER BY e.tabla;

-- S4. Tipos de datos que quedaron en staging (deben ser los mismos de la fuente)
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME LIKE 'stg\_%' ESCAPE '\'
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- S5. Los caracteres con tilde llegaron bien (Latin-1, ver hallazgos del modelo)
SELECT customerID, companyName, city, country
FROM dbo.stg_customers
WHERE companyName LIKE N'%[áéíóúñüöäåçãõ]%' OR city LIKE N'%[áéíóúñüöäåçãõ]%';


-- =====================================================================
-- PARTE B · Base: sqldb-invacom-fuente
-- Comparen con S3: los conteos deben ser iguales.
-- =====================================================================
/*
SELECT t.name AS tabla_fuente, SUM(p.rows) AS filas
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.schema_id = SCHEMA_ID(N'dbo')
GROUP BY t.name
ORDER BY t.name;
*/
