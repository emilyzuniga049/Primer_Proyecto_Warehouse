-- =============================================
-- Creación de tablas del DW - Invacom Inc S.A.
-- Base: sqldb-invacom-dw
-- =============================================

DROP TABLE IF EXISTS fact_ventas;
DROP TABLE IF EXISTS dim_cliente;
DROP TABLE IF EXISTS dim_producto;
DROP TABLE IF EXISTS dim_empleado;
DROP TABLE IF EXISTS dim_transportista;
DROP TABLE IF EXISTS dim_tiempo;
GO

-- ---------- Dimensiones ----------

CREATE TABLE dim_cliente (
    cliente_key     INT IDENTITY(1,1) PRIMARY KEY,
    cliente_id      NVARCHAR(10)  NOT NULL,
    empresa         NVARCHAR(100) NOT NULL,
    contacto        NVARCHAR(100) NULL,
    cargo_contacto  NVARCHAR(100) NULL,
    ciudad          NVARCHAR(50)  NULL,
    pais            NVARCHAR(50)  NULL,
    region          NVARCHAR(30)  NULL
);

CREATE TABLE dim_producto (
    producto_key          INT IDENTITY(1,1) PRIMARY KEY,
    producto_id           INT           NOT NULL,
    producto              NVARCHAR(100) NOT NULL,
    cantidad_por_unidad   NVARCHAR(50)  NULL,
    precio_lista          DECIMAL(10,2) NULL,
    descontinuado         NVARCHAR(2)   NULL,
    categoria             NVARCHAR(50)  NULL,
    descripcion_categoria NVARCHAR(200) NULL
);

CREATE TABLE dim_empleado (
    empleado_key  INT IDENTITY(1,1) PRIMARY KEY,
    empleado_id   INT           NOT NULL,
    nombre        NVARCHAR(100) NOT NULL,
    puesto        NVARCHAR(100) NULL,
    ciudad        NVARCHAR(50)  NULL,
    pais          NVARCHAR(50)  NULL,
    supervisor    NVARCHAR(100) NULL
);

CREATE TABLE dim_transportista (
    transportista_key  INT IDENTITY(1,1) PRIMARY KEY,
    transportista_id   INT           NOT NULL,
    transportista      NVARCHAR(100) NOT NULL
);

CREATE TABLE dim_tiempo (
    fecha_key         INT PRIMARY KEY,
    fecha             DATE         NOT NULL,
    anio              INT          NOT NULL,
    trimestre         INT          NOT NULL,
    mes               INT          NOT NULL,
    nombre_mes        NVARCHAR(15) NOT NULL,
    dia               INT          NOT NULL,
    nombre_dia        NVARCHAR(15) NOT NULL,
    es_fin_de_semana  NVARCHAR(2)  NOT NULL
);
GO

-- ---------- Tabla de hechos ----------

CREATE TABLE fact_ventas (
    venta_key          INT IDENTITY(1,1) PRIMARY KEY,
    fecha_key          INT NOT NULL REFERENCES dim_tiempo(fecha_key),
    cliente_key        INT NOT NULL REFERENCES dim_cliente(cliente_key),
    producto_key       INT NOT NULL REFERENCES dim_producto(producto_key),
    empleado_key       INT NOT NULL REFERENCES dim_empleado(empleado_key),
    transportista_key  INT NOT NULL REFERENCES dim_transportista(transportista_key),
    pedido_id          INT           NOT NULL,
    cantidad           INT           NOT NULL,
    precio_unitario    DECIMAL(10,2) NOT NULL,
    descuento          DECIMAL(4,2)  NOT NULL,
    monto_bruto        DECIMAL(12,2) NOT NULL,
    monto_descuento    DECIMAL(12,2) NOT NULL,
    monto_neto         DECIMAL(12,2) NOT NULL,
    flete_prorrateado  DECIMAL(10,2) NULL,
    dias_entrega       INT           NULL,
    enviado            NVARCHAR(2)   NOT NULL
);
GO

-- ---------- Filas -1 "Desconocido" ----------

SET IDENTITY_INSERT dim_cliente ON;
INSERT INTO dim_cliente (cliente_key, cliente_id, empresa, contacto, cargo_contacto, ciudad, pais, region)
VALUES (-1, 'N/A', 'Desconocido', 'Desconocido', 'Desconocido', 'Desconocido', 'Desconocido', 'Desconocido');
SET IDENTITY_INSERT dim_cliente OFF;

SET IDENTITY_INSERT dim_producto ON;
INSERT INTO dim_producto (producto_key, producto_id, producto, cantidad_por_unidad, precio_lista, descontinuado, categoria, descripcion_categoria)
VALUES (-1, -1, 'Desconocido', 'Desconocido', 0, 'No', 'Desconocido', 'Desconocido');
SET IDENTITY_INSERT dim_producto OFF;

SET IDENTITY_INSERT dim_empleado ON;
INSERT INTO dim_empleado (empleado_key, empleado_id, nombre, puesto, ciudad, pais, supervisor)
VALUES (-1, -1, 'Desconocido', 'Desconocido', 'Desconocido', 'Desconocido', 'Desconocido');
SET IDENTITY_INSERT dim_empleado OFF;

SET IDENTITY_INSERT dim_transportista ON;
INSERT INTO dim_transportista (transportista_key, transportista_id, transportista)
VALUES (-1, -1, 'Desconocido');
SET IDENTITY_INSERT dim_transportista OFF;

INSERT INTO dim_tiempo (fecha_key, fecha, anio, trimestre, mes, nombre_mes, dia, nombre_dia, es_fin_de_semana)
VALUES (-1, '1900-01-01', 1900, 0, 0, 'Desconocido', 0, 'Desconocido', 'No');
GO
