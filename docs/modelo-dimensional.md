# Modelo dimensional – DW Invacom Inc S.A.

## 1. Tipo de modelo
Se utiliza un **esquema estrella**: una tabla de hechos central (`fact_ventas`) conectada directamente a cinco dimensiones desnormalizadas.

**Justificación:**
- Menos joins, por lo que las consultas y las tablas dinámicas en Excel son más simples y rápidas.
- Más fácil de construir y mantener con Azure Data Factory.
- Es el enfoque estándar para el análisis de ventas (Kimball).

## 2. Proceso de negocio
**Ventas de productos** de Invacom: pedidos de clientes y sus líneas de detalle.

## 3. Granularidad
**Una fila por cada producto dentro de cada pedido** (nivel de línea de `order_details`).

Es el nivel más detallado disponible y permite analizar las ventas por cliente, producto, empleado, transportista o fecha sin perder información. Volumen esperado: 2 155 filas (830 pedidos, 2,6 líneas promedio por pedido).

## 4. Diagrama

```
                    dim_cliente
                         |
  dim_empleado ——— fact_ventas ——— dim_producto
                    /         \
          dim_tiempo           dim_transportista
```

## 5. Tabla de hechos: `fact_ventas`

| Columna | Tipo | Origen / cálculo |
|---|---|---|
| venta_key | INT IDENTITY (PK) | Llave sustituta |
| fecha_key | INT (FK) | `orders.orderDate` en formato AAAAMMDD |
| cliente_key | INT (FK) | Búsqueda en `dim_cliente` por `orders.customerID` |
| producto_key | INT (FK) | Búsqueda en `dim_producto` por `order_details.productID` |
| empleado_key | INT (FK) | Búsqueda en `dim_empleado` por `orders.employeeID` |
| transportista_key | INT (FK) | Búsqueda en `dim_transportista` por `orders.shipperID` |
| pedido_id | INT | `orders.orderID` (dimensión degenerada) |
| cantidad | INT | `order_details.quantity` |
| precio_unitario | DECIMAL(10,2) | `order_details.unitPrice` |
| descuento | DECIMAL(4,2) | `order_details.discount` (0 a 0,25) |
| monto_bruto | DECIMAL(12,2) | cantidad × precio_unitario |
| monto_descuento | DECIMAL(12,2) | monto_bruto × descuento |
| monto_neto | DECIMAL(12,2) | monto_bruto − monto_descuento |
| flete_prorrateado | DECIMAL(10,2) | `orders.freight` repartido según el peso de la línea en el total del pedido |
| dias_entrega | INT NULL | `shippedDate` − `orderDate`; NULL si el pedido no se ha enviado |
| enviado | VARCHAR(2) | "Sí" / "No" según exista `shippedDate` |

## 6. Dimensiones

### `dim_cliente` (91 clientes, 21 países)
Fuente: `customers`

| Columna | Origen |
|---|---|
| cliente_key (PK) | Llave sustituta |
| cliente_id | `customers.customerID` |
| empresa | `customers.companyName` |
| contacto | `customers.contactName` |
| cargo_contacto | `customers.contactTitle` |
| ciudad | `customers.city` |
| pais | `customers.country` |
| region | Derivada del país (Norteamérica, Latinoamérica, Europa) |

### `dim_producto` (77 productos, 8 categorías)
Fuente: `products` + `categories`

| Columna | Origen |
|---|---|
| producto_key (PK) | Llave sustituta |
| producto_id | `products.productID` |
| producto | `products.productName` |
| cantidad_por_unidad | `products.quantityPerUnit` |
| precio_lista | `products.unitPrice` |
| descontinuado | `products.discontinued` (0/1) → "No" / "Sí" |
| categoria | `categories.categoryName` |
| descripcion_categoria | `categories.description` |

### `dim_empleado` (9 empleados)
Fuente: `employees`

| Columna | Origen |
|---|---|
| empleado_key (PK) | Llave sustituta |
| empleado_id | `employees.employeeID` |
| nombre | `employees.employeeName` |
| puesto | `employees.title` |
| ciudad | `employees.city` |
| pais | `employees.country` |
| supervisor | Nombre del jefe, resuelto con `employees.reportsTo`; "Sin supervisor" si es NULL |

### `dim_transportista` (3 transportistas)
Fuente: `shippers`

| Columna | Origen |
|---|---|
| transportista_key (PK) | Llave sustituta |
| transportista_id | `shippers.shipperID` |
| transportista | `shippers.companyName` |

### `dim_tiempo` (01/01/2013 al 31/12/2015)
Generada en el ETL; cubre los años completos del rango de pedidos (jul 2013 a may 2015).

| Columna | Ejemplo |
|---|---|
| fecha_key (PK) | 20130704 |
| fecha | 2013-07-04 |
| anio | 2013 |
| trimestre | 3 |
| mes | 7 |
| nombre_mes | Julio |
| dia | 4 |
| nombre_dia | Jueves |
| es_fin_de_semana | No |

## 7. Reglas generales
- Todas las dimensiones usan **llave sustituta** (`*_key`) y conservan la llave original (`*_id`).
- Cada dimensión tiene una fila **-1 "Desconocido"** para hechos con referencias faltantes.
- La carga pasa primero por tablas **staging** (`stg_*`), copia directa de la fuente; después se limpia y transforma hacia las dimensiones y los hechos.
- Orden de carga: staging → dimensiones → hechos.

## 8. Hallazgos de calidad que afectan el modelo
| Tabla | Hallazgo | Tratamiento |
|---|---|---|
| orders | 21 pedidos sin `shippedDate` | `dias_entrega` en NULL y `enviado` = "No" |
| employees | 1 empleado sin `reportsTo` (vicepresidente) | `supervisor` = "Sin supervisor" |
| customers, products | Archivos originales en codificación Latin-1 | Se verificó que la carga a Azure conservó correctamente los caracteres con tilde |
| products | `discontinued` como 0/1 | Convertir a "No" / "Sí" |

## 9. Preguntas de negocio que responde
- ¿Cuánto se vende por país, región y cliente?
- ¿Qué categorías y productos generan más ingresos?
- ¿Cuál es el desempeño de ventas de cada empleado?
- ¿Cómo evolucionan las ventas por mes, trimestre y año?
- ¿Qué transportista entrega más rápido y cuánto cuesta el flete?
- ¿Cuánto se deja de ganar por descuentos?
