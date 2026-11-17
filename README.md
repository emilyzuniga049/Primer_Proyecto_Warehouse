# Proyecto Data Warehouse – Invacom Inc S.A.

Proyecto #1 de Minería de Datos (Universidad Técnica Nacional, Sede Regional de San Carlos, 3C2026).
Implementación de un *data warehouse* en Microsoft Azure con un esquema estrella, un proceso ETL en Azure Data Factory e informes en Excel conectados al DW.

- **Profesor:** Freddy Rocha Boza
- **Tablero Scrum (Trello):** https://trello.com/b/HrmnNVrI

## Integrantes

| Integrante | Rol y aporte principal |
|---|---|
| Emily Zúñiga Solano | Extracción a *staging* (`pl_extraccion_stg`) y bitácora de cargas |
| Juan Daniel Gómez Cubillo | Carga de dimensiones (`pl_carga_dimensiones`) |
| John Alejandro Araya Echeverría | *Scrum Master*; creación del DW, carga de hechos (`pl_carga_hechos`) y tablas dinámicas en Excel |
| Ryan Eliecer Vega Solano | Orquestación (`pl_etl_completo`) y validación del DW |

## Tecnologías

- **Azure SQL Database:** base fuente y *data warehouse*
- **Azure Data Factory:** proceso ETL (*pipelines*, Mapping Data Flows y procedimientos almacenados)
- **Excel con Power Query y Power Pivot:** tablas dinámicas conectadas al DW
- **Scrum:** *sprints* de una semana gestionados en Trello

## Estructura del repositorio

- `docs/` – documento final del proyecto, modelo dimensional y registro de *sprints*
- `sql/` – scripts de análisis de calidad, creación, carga y verificación del DW
- `adf/` – *pipelines*, flujos de datos y conjuntos de datos de Azure Data Factory (sincronizados desde ADF Studio)
- `excel/` – libro `Invacom_TablasDinamicas.xlsx` con las tablas dinámicas

## Recursos en Azure

Todos están en el grupo de recursos `rg-invacom-dw`, región West US.

| Recurso | Nombre |
|---|---|
| Servidor SQL | `sql-invacom-john` |
| Base fuente | `sqldb-invacom-fuente` |
| Base del DW | `sqldb-invacom-dw` |
| Data Factory | `adf-invacom-john` |

Las credenciales no se guardan en el repositorio. Los servicios vinculados usan autenticación SQL y la contraseña se configura directamente en Data Factory.

## Modelo dimensional

Esquema estrella con la tabla de hechos `fact_ventas` (una fila por línea de pedido, 2 155 filas) y cinco dimensiones: `dim_tiempo`, `dim_cliente`, `dim_producto`, `dim_empleado` y `dim_transportista`. Cada dimensión tiene una llave sustituta y una fila −1 "Desconocido".

## Proceso ETL

```
sqldb-invacom-fuente ──► stg_* ──► dimensiones ──► fact_ventas
                    (extracción)  (Data Flows)   (procedimiento)
```

| *Pipeline* | Qué hace |
|---|---|
| `pl_extraccion_stg` | Copia las 7 tablas de la fuente a tablas `stg_*` dentro del DW |
| `pl_carga_dimensiones` | Limpia los datos y carga las 5 dimensiones con *upsert* |
| `pl_carga_hechos` | Ejecuta `usp_cargar_fact_ventas`, que recarga `fact_ventas` dentro de una transacción |
| `pl_etl_completo` | Ejecuta las tres etapas en orden |

Cada carga queda registrada en la tabla `etl_log_carga`. El ETL se puede ejecutar varias veces sin duplicar datos.

### Scripts principales (`sql/`)

| Script | Uso |
|---|---|
| `04_creacion_dw_sqlserver.sql` | Crea las tablas del DW |
| `05_staging_control_sqlserver.sql` | Crea la bitácora `etl_log_carga` y `usp_registrar_carga` |
| `07_verificacion_staging_sqlserver.sql` | Verifica la carga de *staging* |
| `09_…` | Verifica la carga de dimensiones |
| `10_fact_ventas_sqlserver.sql` | Crea `usp_cargar_fact_ventas` |
| `12_validacion_dw_sqlserver.sql` | Validación completa del DW (75 revisiones) |

## Cómo ejecutar

1. Ejecutar los scripts de creación (`04`, `05`, `08` y `10`) en `sqldb-invacom-dw`.
2. En ADF Studio, ejecutar `pl_etl_completo` (Desencadenar ahora o Depurar).
3. Ejecutar `12_validacion_dw_sqlserver.sql` y confirmar que todas las revisiones estén en OK.
4. Abrir `excel/Invacom_TablasDinamicas.xlsx` y usar **Datos → Actualizar todo**.

La base usa la oferta gratuita de Azure y se pausa sola. La primera conexión después de una pausa puede tardar cerca de un minuto.

## Resultados

- 2 155 filas en `fact_ventas`, ninguna en "Desconocido"
- Totales iguales a la fuente: ventas netas de 1 265 792,76 en 830 pedidos
- 75 de 75 revisiones de validación en OK
- 5 tablas dinámicas en Excel: ventas por región, producto, empleado y periodo, y desempeño de transportistas
