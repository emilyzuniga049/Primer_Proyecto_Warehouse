-- =====================================================================
-- INVACOM DW · PERMISOS DE AZURE DATA FACTORY (SQL Server / T-SQL)
-- Los linked services de ADF usan la identidad administrada de
-- adf-invacom-john: no hay usuario ni contraseña en el repositorio.
--
-- REQUISITOS
--   1. Portal → servidor sql-invacom-john → Microsoft Entra ID → Set admin → Save.
--   2. Conectarse con esa cuenta de Entra (SSMS: Authentication = "Microsoft Entra MFA",
--      o el Query editor de cada base en el portal). Con el login SQL,
--      CREATE USER ... FROM EXTERNAL PROVIDER da error.
--   3. Haber ejecutado 05_staging_control_sqlserver.sql en sqldb-invacom-dw.
--
-- Este archivo tiene DOS partes, una por base. Ejecuten cada parte por separado,
-- seleccionándola y presionando F5 con la base correcta en la lista desplegable.
-- =====================================================================


-- =====================================================================
-- PARTE A · Base: sqldb-invacom-fuente
-- La fuente solo se lee: el ETL nunca escribe en ella.
-- =====================================================================
IF DATABASE_PRINCIPAL_ID(N'adf-invacom-john') IS NULL
    CREATE USER [adf-invacom-john] FROM EXTERNAL PROVIDER;

ALTER ROLE db_datareader ADD MEMBER [adf-invacom-john];

SELECT dp.name AS usuario, r.name AS rol
FROM sys.database_principals dp
JOIN sys.database_role_members rm ON rm.member_principal_id = dp.principal_id
JOIN sys.database_principals r    ON r.principal_id = rm.role_principal_id
WHERE dp.name = N'adf-invacom-john';
GO


-- =====================================================================
-- PARTE B · Base: sqldb-invacom-dw
-- =====================================================================
IF DATABASE_PRINCIPAL_ID(N'adf-invacom-john') IS NULL
    CREATE USER [adf-invacom-john] FROM EXTERNAL PROVIDER;

ALTER ROLE db_datareader ADD MEMBER [adf-invacom-john];   -- leer stg_, dim_, fact_
ALTER ROLE db_datawriter ADD MEMBER [adf-invacom-john];   -- cargar stg_, dim_, fact_
ALTER ROLE db_ddladmin   ADD MEMBER [adf-invacom-john];   -- crear tablas stg_ (autoCreate) y TRUNCATE
GRANT EXECUTE ON OBJECT::dbo.usp_registrar_carga TO [adf-invacom-john];

SELECT dp.name AS usuario, r.name AS rol
FROM sys.database_principals dp
JOIN sys.database_role_members rm ON rm.member_principal_id = dp.principal_id
JOIN sys.database_principals r    ON r.principal_id = rm.role_principal_id
WHERE dp.name = N'adf-invacom-john';
GO
