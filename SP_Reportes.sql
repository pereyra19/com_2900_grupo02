/*Reporte 1 
Se desea analizar el flujo de caja en forma semanal. Debe presentar la recaudación por 
pagos ordinarios y extraordinarios de cada semana, el promedio en el periodo, y el 
acumulado progresivo. */

-----------------------------------------------------------------------------------
-- RPT-01: Flujo de caja semanal (total recaudado)
--   Ventana por fecha de pago y filtro opcional por consorcio.
--   NO clasifica ordinario/extraordinario (no se inventan categorías).
-----------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.rpt_FlujoCajaSemanal
    @FechaDesde   date,
    @FechaHasta   date,
    @IdConsorcio  int = NULL     -- NULL = todos los consorcios
AS
BEGIN
    SET NOCOUNT ON;

    -- Tomamos lunes como inicio de semana (base Monday 2001-01-01)
    DECLARE @BaseMonday date = '20010101';

    ;WITH pagos AS (
        SELECT
            p.fechaPago,
            p.monto,
            uf.idConsorcio
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf
          ON uf.idUF = p.nroUnidadFuncional
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY, 1, @FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    ),
    semanas AS (
        SELECT
            semana_ini = DATEADD(WEEK, DATEDIFF(WEEK, @BaseMonday, p.fechaPago), @BaseMonday),
            p.monto
        FROM pagos p
    ),
    totales AS (
        SELECT
            semana_ini,
            total = SUM(monto)
        FROM semanas
        GROUP BY semana_ini
    )
    SELECT
        semana_ini,
        semana_fin       = DATEADD(DAY, 6, semana_ini),
        total,
        promedio_periodo = AVG(total) OVER (),  -- promedio de todas las semanas del rango
        acumulado        = SUM(total) OVER (ORDER BY semana_ini
                                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    FROM totales
    ORDER BY semana_ini;
END
GO

----------------------------------------------------------------------------------------------
/*                                           Reporte 2 
Presente el total de recaudación por mes y departamento en formato de tabla cruzada.  */ 
------------------------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE dbo.rpt_RecaudacionMesDepartamento
    @FechaDesde   date,
    @FechaHasta   date,
    @IdConsorcio  int  = NULL,  -- NULL = todos
    @AsXml        bit  = 0      -- 1 = devuelve XML
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#base') IS NOT NULL DROP TABLE #base;

    -- Base: pagos en el rango, con mes contable y depto
    SELECT
        mes          = DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1),
        departamento = UPPER(LTRIM(RTRIM(COALESCE(uf.departamento,'(SIN)')))),
        monto        = p.monto
    INTO #base
    FROM dbo.Pago p
    JOIN dbo.UnidadFuncional uf
      ON uf.idUF = p.nroUnidadFuncional
    WHERE p.fechaPago >= @FechaDesde
      AND p.fechaPago <  DATEADD(DAY, 1, @FechaHasta)
      AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio);

    -- Si no hay datos, responder vacío (o XML vacío)
    IF NOT EXISTS (SELECT 1 FROM #base)
    BEGIN
        IF @AsXml = 1
            SELECT CAST('<reporte/>' AS xml) AS xml_out;
        ELSE
            SELECT CAST(NULL AS date) AS mes WHERE 1=0;
        RETURN;
    END

    -- Columnas del PIVOT (departamentos encontrados)
    DECLARE @cols nvarchar(max) =
      STUFF((
        SELECT DISTINCT ',' + QUOTENAME(departamento)
        FROM #base
        FOR XML PATH(''), TYPE).value('.','nvarchar(max)')
      ,1,1,'');

    -- PIVOT dinámico. Si @AsXml = 1, lo devolvemos en XML.
    DECLARE @sql nvarchar(max) =
       N'SELECT mes,' + @cols + N'
         FROM (SELECT mes, departamento, monto FROM #base) d
         PIVOT (SUM(monto) FOR departamento IN (' + @cols + N')) p ' +
         CASE WHEN @AsXml=1
              THEN N'FOR XML PATH(''fila''), ROOT(''reporte''), TYPE;'
              ELSE N'ORDER BY mes;'
         END;

    EXEC sys.sp_executesql @sql;
END
GO

-- Todos los consorcios, año 2025, salida tabular
EXEC dbo.rpt_RecaudacionMesDepartamento
     @FechaDesde='2025-01-01', @FechaHasta='2025-12-31',
     @IdConsorcio=NULL, @AsXml=0;

-- Sólo un consorcio (por id), en XML
EXEC dbo.rpt_RecaudacionMesDepartamento
     @FechaDesde='2025-01-01', @FechaHasta='2025-12-31',
     @IdConsorcio=1, @AsXml=1;

-------------------------------------------------------------------------------------
/*                                      Reporte 3 
Presente un cuadro cruzado con la recaudación total desagregada según su procedencia  
(ordinario, extraordinario, etc.) según el periodo.  */
-------------------------------------------------------------------------------------


-------------------------------------------------------------------------------------
/*                                      Reporte 4 
Obtenga los 5 (cinco) meses de mayores gastos y los 5 (cinco) de mayores ingresos. */
-------------------------------------------------------------------------------------



-------------------------------------------------------------------------------------
/*                                      Reporte 5 
Obtenga los 3 (tres) propietarios con mayor morosidad. Presente información de contacto y 
DNI de los propietarios para que la administración los pueda contactar o remitir el trámite al 
estudio jurídico. */
-------------------------------------------------------------------------------------



-------------------------------------------------------------------------------------
/*                                        Reporte 6 
Muestre las fechas de pagos de expensas ordinarias de cada UF y la cantidad de días que 
pasan entre un pago y el siguiente, para el conjunto examinado. */
-------------------------------------------------------------------------------------



USE Com3900G02;
GO
/* ============================================================
   R1 — Flujo de caja semanal: ordinario vs extraordinario (TABULAR)
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.rpt_R1_FlujoCajaSemanal
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL      -- NULL = todos
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BaseMonday date = '20010101';

    ;WITH pagos AS (
        SELECT
            p.id,
            p.fechaPago,
            p.monto,
            uf.idConsorcio,
            -- Si no hay marca en detalle/categoría → se considera ordinario
            esExtra = CASE WHEN EXISTS (
                          SELECT 1
                          FROM dbo.PagoExpensa pe
                          JOIN dbo.DetalleExpensa d ON d.idExpensa = pe.idExpensa
                          WHERE pe.idPago = p.id
                            AND (d.categoria LIKE '%extra%' OR d.tipo LIKE '%extra%')
                       ) THEN 1 ELSE 0 END
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    ),
    sem AS (
        SELECT
            semana_ini = DATEADD(WEEK, DATEDIFF(WEEK, @BaseMonday, fechaPago), @BaseMonday),
            rec_ordi   = SUM(CASE WHEN esExtra = 0 THEN monto ELSE 0 END),
            rec_extra  = SUM(CASE WHEN esExtra = 1 THEN monto ELSE 0 END)
        FROM pagos
        GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, @BaseMonday, fechaPago), @BaseMonday)
    )
    SELECT
        semana_ini,
        semana_fin        = DATEADD(DAY,6,semana_ini),
        ordinarios        = rec_ordi,
        extraordinarios   = rec_extra,
        total             = rec_ordi + rec_extra,
        promedio_periodo  = AVG(rec_ordi + rec_extra) OVER (),
        acumulado         = SUM(rec_ordi + rec_extra) OVER (ORDER BY semana_ini
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    FROM sem
    ORDER BY semana_ini;
END
GO

/* ============================================================
   R2 — Recaudación por MES y DEPARTAMENTO (PIVOT DINÁMICO → XML)
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.rpt_R2_RecaudacionMesDepto_XML
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL      -- NULL = todos
AS
BEGIN
    SET NOCOUNT ON;

    /* armamos la lista de columnas [YYYY-MM] presentes en el rango */
    DECLARE @cols nvarchar(max);

    ;WITH meses AS (
        SELECT DISTINCT
            mes_key = CONVERT(char(7), DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1), 126)
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    )
    SELECT @cols = STRING_AGG(QUOTENAME(mes_key), ',') WITHIN GROUP (ORDER BY mes_key)
    FROM meses;

    IF @cols IS NULL
    BEGIN
        -- sin datos → XML vacío con raíz
        SELECT CAST('<RecaudacionMesDepto/>' AS xml) AS XMLResult;
        RETURN;
    END

    DECLARE @sql nvarchar(max) = N'
;WITH base AS (
   SELECT
     c.nombre          AS consorcio,
     uf.departamento   AS departamento,
     CONVERT(char(7), DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1), 126) AS mes_key,
     p.monto           AS monto
   FROM dbo.Pago p
   JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
   JOIN dbo.Consorcio c        ON c.id = uf.idConsorcio
   WHERE p.fechaPago >= @FechaDesde
     AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta)
     AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
),
agg AS (
   SELECT consorcio, departamento, mes_key, total = SUM(monto)
   FROM base
   GROUP BY consorcio, departamento, mes_key
)
SELECT
  consorcio AS [row/@consorcio],
  departamento AS [row/@depto], ' + @cols + N'
FROM (
  SELECT consorcio, departamento, mes_key, total
  FROM agg
) src
PIVOT (SUM(total) FOR mes_key IN (' + @cols + N')) p
FOR XML PATH(''row''), ROOT(''RecaudacionMesDepto''), TYPE;';

    EXEC sp_executesql @sql,
        N'@FechaDesde date, @FechaHasta date, @IdConsorcio int',
        @FechaDesde, @FechaHasta, @IdConsorcio;
END
GO

/* ============================================================
   R3 — Cuadro cruzado de recaudación por procedencia (TABULAR)
         (periodo = mes; columnas = Ordinario/Extraordinario)
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.rpt_R3_RecaudacionPorProcedencia
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH base AS (
        SELECT
            mes = DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1),
            procedencia = CASE WHEN EXISTS (
                              SELECT 1
                              FROM dbo.PagoExpensa pe
                              JOIN dbo.DetalleExpensa d ON d.idExpensa = pe.idExpensa
                              WHERE pe.idPago = p.id
                                AND (d.categoria LIKE '%extra%' OR d.tipo LIKE '%extra%')
                           ) THEN 'Extraordinario' ELSE 'Ordinario' END,
            p.monto
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    ),
    agg AS (
        SELECT mes, procedencia, total = SUM(monto)
        FROM base
        GROUP BY mes, procedencia
    )
    SELECT
        mes,
        Ordinario      = SUM(CASE WHEN procedencia='Ordinario'     THEN total ELSE 0 END),
        Extraordinario = SUM(CASE WHEN procedencia='Extraordinario' THEN total ELSE 0 END),
        Total          = SUM(total)
    FROM agg
    GROUP BY mes
    ORDER BY mes;
END
GO

/* ============================================================
   R4 — Top 5 meses de MAYORES GASTOS y de MAYORES INGRESOS (TABULAR)
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.rpt_R4_Top5Meses_GastosIngresos
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @d1 date = DATEFROMPARTS(YEAR(@FechaDesde), MONTH(@FechaDesde), 1);
    DECLARE @d2 date = DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(@FechaHasta), MONTH(@FechaHasta), 1)); -- exclusivo

    ;WITH ing AS (
        SELECT mes = DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1),
               total = SUM(p.monto)
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
        WHERE p.fechaPago >= @FechaDesde AND p.fechaPago < DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio=@IdConsorcio)
        GROUP BY DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1)
    ),
    gas AS (
        SELECT mes = DATEFROMPARTS(YEAR(e.periodo), MONTH(e.periodo), 1),
               total = SUM(d.importe)
        FROM dbo.DetalleExpensa d
        JOIN dbo.Expensa e          ON e.id = d.idExpensa
        JOIN dbo.UnidadFuncional uf ON uf.idUF = e.idUF
        WHERE e.periodo >= @d1 AND e.periodo < @d2
          AND (@IdConsorcio IS NULL OR uf.idConsorcio=@IdConsorcio)
        GROUP BY DATEFROMPARTS(YEAR(e.periodo), MONTH(e.periodo), 1)
    )
    SELECT TOP 5 'INGRESOS' AS tipo, mes, total
    FROM ing
    ORDER BY total DESC, mes DESC;

    SELECT TOP 5 'GASTOS' AS tipo, mes, total
    FROM gas
    ORDER BY total DESC, mes DESC;
END
GO

/* ============================================================
   R5 — Top N propietarios con mayor morosidad (TABULAR)
         morosidad = Expensas (<= mes de corte) − Pagos (<= corte)
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.rpt_R5_TopMorosos
    @FechaCorte  date,
    @IdConsorcio int = NULL,
    @TopN        int = 3
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH mapUF AS (
        -- Vinculación Persona ↔ UF por CBU (como en importaciones)
        SELECT
            per.id          AS idPersona,
            per.nombre,
            per.apellido,
            per.dni,
            per.email,
            per.telefono,
            uf.idUF,
            uf.idConsorcio
        FROM dbo.Persona per
        JOIN dbo.UnidadFuncional uf
          ON uf.cbu_cvu_actual = per.cbu_cvu
        WHERE per.tipoTitularidad = 'Propietario'
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    ),
    pag AS (
        SELECT m.idPersona, total_pagos = SUM(p.monto)
        FROM mapUF m
        JOIN dbo.Pago p ON p.nroUnidadFuncional = m.idUF
        WHERE p.fechaPago <= @FechaCorte
        GROUP BY m.idPersona
    ),
    exp AS (
        SELECT m.idPersona, total_exp = SUM(e.montoTotal)
        FROM mapUF m
        JOIN dbo.Expensa e ON e.idUF = m.idUF
        WHERE e.periodo <= EOMONTH(@FechaCorte)
        GROUP BY m.idPersona
    ),
    base AS (
        SELECT
            m.idPersona, m.nombre, m.apellido, m.dni, m.email, m.telefono,
            pagos = COALESCE(p.total_pagos,0),
            expen = COALESCE(x.total_exp,0),
            deuda = COALESCE(x.total_exp,0) - COALESCE(p.total_pagos,0)
        FROM mapUF m
        LEFT JOIN pag p ON p.idPersona = m.idPersona
        LEFT JOIN exp x ON x.idPersona = m.idPersona
    )
    SELECT TOP (@TopN)
        nombre, apellido, dni, email, telefono,
        pagos, expen, deuda
    FROM base
    WHERE deuda > 0
    ORDER BY deuda DESC, apellido, nombre;
END
GO

/* ============================================================
   R6 — Fechas de pagos (ordinarios) por UF + días hasta el siguiente (XML)
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.rpt_R6_PagosOrdinarios_GAP_XML
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH pagos AS (
        SELECT
            uf.idUF, uf.numeroUnidad, c.nombre AS consorcio, p.fechaPago
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
        JOIN dbo.Consorcio c        ON c.id = uf.idConsorcio
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
          -- filtro a "ordinarias": si hay marca de extra en el pago lo excluimos
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.PagoExpensa pe
                JOIN dbo.DetalleExpensa d ON d.idExpensa = pe.idExpensa
                WHERE pe.idPago = p.id
                  AND (d.categoria LIKE '%extra%' OR d.tipo LIKE '%extra%')
          )
    )
    SELECT
      idUF         AS [UF/@idUF],
      numeroUnidad AS [UF/@nro],
      consorcio    AS [UF/@consorcio],
      (
        SELECT
           p1.fechaPago                         AS [pago/@fecha],
           DATEDIFF(DAY, p1.fechaPago,
                    LEAD(p1.fechaPago) OVER (PARTITION BY p1.idUF ORDER BY p1.fechaPago))
                                               AS [pago/@dias_hasta_siguiente]
        FROM pagos p1
        WHERE p1.idUF = p.idUF
        ORDER BY p1.fechaPago
        FOR XML PATH(''), TYPE
      )
    FROM pagos p
    GROUP BY idUF, numeroUnidad, consorcio
    ORDER BY consorcio, numeroUnidad
    FOR XML PATH(''), ROOT('PagosUF'), TYPE;
END
GO




















