USE Com3900G02;
GO
/*
   R1 — Flujo de caja semanal: ordinario vs extraordinario
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R1_FlujoCajaSemanal
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL      -- NULL = todos los consorcios
AS
BEGIN
    SET NOCOUNT ON;

    -- se toma un lunes como inicio de semana
    DECLARE @BaseMonday date = '20010101';

    WITH pagos AS (
        -- Filtramos pagos dentro del rango y sólo los que tienen UF vinculada
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
        -- Calculamos el lunes de cada pago
        SELECT  semana_ini = DATEADD(WEEK, -- devuelde el lunes donde cae fechaPago 
                    DATEDIFF(WEEK, @BaseMonday, p.fechaPago), -- devuelve un entero para cuantas semanas separon desde base hasta fechaPago
                    @BaseMonday),
            p.monto
        FROM pagos p
    ),
    totales AS (
        -- Total recaudado por semana
        SELECT semana_ini, total_semana = SUM(monto) -- suma los montos de la semana
        FROM semanas
        GROUP BY semana_ini
    )
    SELECT
        semana_ini,
        semana_fin       = DATEADD(DAY, 6, semana_ini),
        total_semana,                                         -- recaudación semanal
        promedio_periodo = AVG(total_semana) OVER (),         -- promedio de todas las semanas del rango
        acumulado        = SUM(total_semana) OVER (ORDER BY semana_ini ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)-- acumulado progresivo
    FROM totales
    ORDER BY semana_ini;
END
GO


/* 
   R2 — Recaudación por MES y DEPARTAMENTO (PIVOT DINÁMICO) en XML
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R2_RecaudacionMesDepto_XML
    @FechaDesde  DATE,
    @FechaHasta  DATE,
    @IdConsorcio INT = NULL      -- NULL = todos
AS
BEGIN
    SET NOCOUNT ON;

    -- pagos por mes y departamento
    IF OBJECT_ID('tempdb..#R2_MesDepto') IS NOT NULL
        DROP TABLE #R2_MesDepto;

    SELECT
        consorcio    = c.nombre,
        departamento = uf.departamento,
        -- se convierte a char(7) YYYY-MM para pivotear y mostrar en XML
        mes_key      = CONVERT(CHAR(7),
                               DATEFROMPARTS(YEAR(p.fechaPago),
                                             MONTH(p.fechaPago),
                                             1),
                               126), -- 126 => formato ISO (YYYY-MM-...)
        monto        = p.monto
    INTO #R2_MesDepto
    FROM dbo.Pago p
    JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
    JOIN dbo.Consorcio       c  ON c.id    = uf.idConsorcio
    WHERE p.fechaPago >= @FechaDesde
      AND p.fechaPago <  DATEADD(DAY, 1, @FechaHasta)
      AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio);

    DECLARE @cols    NVARCHAR(MAX);
    DECLARE @colsXml NVARCHAR(MAX);
    DECLARE @sql     NVARCHAR(MAX);

    /* columnas dinámicas para el PIVOT */
    SELECT @cols =
        STRING_AGG(QUOTENAME(mes_key), ',')
        WITHIN GROUP (ORDER BY mes_key)
    FROM (SELECT DISTINCT mes_key FROM #R2_MesDepto) AS d;

    -- si no hay datos en el rango, devolvemos XML vacío
    IF @cols IS NULL
    BEGIN
        SELECT CAST('<RecaudacionMesDepto />' AS XML) AS Resultado;
        RETURN;
    END;

    /* columnas dinámicas para el SELECT XML (alias válidos como atributos) */
    SELECT @colsXml =
        STRING_AGG(
            'ISNULL(' + QUOTENAME(mes_key) + ', 0) AS [@m_' +
            REPLACE(mes_key, '-', '_') + ']',
            ','
        )
        WITHIN GROUP (ORDER BY mes_key)
    FROM (SELECT DISTINCT mes_key FROM #R2_MesDepto) AS d;

    SET @sql = N'
    WITH agg AS (
        SELECT consorcio, departamento, mes_key, monto
        FROM #R2_MesDepto
    ),
    pivoted AS (
        SELECT
            consorcio,
            departamento,
            ' + @cols + N'
        FROM agg
        PIVOT (
            SUM(monto) FOR mes_key IN (' + @cols + N')
        ) AS p
    )
    SELECT
        consorcio    AS [@consorcio],
        departamento AS [@depto],
        ' + @colsXml + N'
    FROM pivoted
    FOR XML PATH(''row''), ROOT(''RecaudacionMesDepto''), TYPE;
    ';

    EXEC sys.sp_executesql @sql;
END;
GO



/* 
   R3 — Cuadro cruzado de recaudación por procedencia 
         (periodo = mes; columnas = Ordinario/Extraordinario)
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R3_RecaudacionPorProcedencia
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL    -- NULL = todos los consorcios
AS
BEGIN
    SET NOCOUNT ON;

    WITH base AS (
        SELECT
            periodo = DATEFROMPARTS(YEAR(e.periodo), MONTH(e.periodo), 1),   
            -- todo lo que NO sea 'Extraordinario' se considera 'Ordinario'
            procedencia = CASE WHEN d.tipo = 'Extraordinario' THEN 'Extraordinario' ELSE 'Ordinario' END,
            importe     = d.importe
        FROM dbo.DetalleExpensa d
        JOIN dbo.Expensa e ON e.id = d.idExpensa
        JOIN dbo.UnidadFuncional uf ON uf.idUF = e.idUF
        WHERE e.periodo >= @FechaDesde
          AND e.periodo <  DATEADD(DAY, 1, @FechaHasta)   
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    ),
    sub AS (
        SELECT
            periodo,
            procedencia,
            total = SUM(importe)
        FROM base
        GROUP BY periodo, procedencia
    )
    SELECT
        periodo,
        Ordinario      = SUM(CASE WHEN procedencia = 'Ordinario'      THEN total ELSE 0 END),
        Extraordinario = SUM(CASE WHEN procedencia = 'Extraordinario' THEN total ELSE 0 END),
        Total          = SUM(total)
    FROM sub 
    GROUP BY periodo
    ORDER BY periodo;
END
GO




/*
   R4 — Top 5 meses de MAYORES GASTOS y de MAYORES INGRESOS 
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R4_Top5Meses_GastosIngresos
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL      -- NULL = todos los consorcios
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalizo a “primer día del mes” y “primer día del mes siguiente”
    DECLARE @d1 date = DATEFROMPARTS(YEAR(@FechaDesde), MONTH(@FechaDesde), 1);
    DECLARE @d2 date = DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(@FechaHasta), MONTH(@FechaHasta), 1));

    -- 1) Top 5 meses de mayores INGRESOS (Pagos)
    ;WITH ing AS (
        SELECT 
            mes   = DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1),
            total = SUM(p.monto)
        FROM dbo.Pago p
        INNER JOIN dbo.UnidadFuncional uf 
            ON uf.idUF = p.nroUnidadFuncional
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY, 1, @FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
        GROUP BY DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1)
    )
    SELECT TOP 5
        tipo  = 'INGRESOS',
        mes,
        total
    FROM ing
    ORDER BY total DESC, mes DESC;

    -- 2) Top 5 meses de mayores GASTOS (Expensas)
    ;WITH gas AS (
        SELECT
            mes   = DATEFROMPARTS(YEAR(e.periodo), MONTH(e.periodo), 1),
            total = SUM(d.importe)
        FROM dbo.Expensa e
        INNER JOIN dbo.UnidadFuncional uf 
            ON uf.idUF = e.idUF
        INNER JOIN dbo.DetalleExpensa d 
            ON d.idExpensa = e.id
        WHERE e.periodo >= @d1
          AND e.periodo <  @d2
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
        GROUP BY DATEFROMPARTS(YEAR(e.periodo), MONTH(e.periodo), 1)
    )
    SELECT TOP 5
        tipo  = 'GASTOS',
        mes,
        total
    FROM gas
    ORDER BY total DESC, mes DESC;
END;
GO


/* 
   R5 — Top N propietarios con mayor morosidad
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R5_TopMorosos
    @FechaCorte  date,
    @IdConsorcio int = NULL,
    @TopN        int = 3
AS
BEGIN
    SET NOCOUNT ON;

    WITH mapUF AS (
        -- Vinculación Persona y UF por CBU
        SELECT per.id AS idPersona,
            per.nombre,
            per.apellido,
            per.dni,
            per.email,
            per.telefono,
            uf.idUF,
            uf.idConsorcio
        FROM dbo.Persona per
        JOIN dbo.UnidadFuncional uf ON uf.cbu_cvu_actual = per.cbu_cvu
        WHERE per.tipoTitularidad = 'Inquilino' --filtramos por Inquilino  
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    ),
    pag AS (
        SELECT m.idPersona, total_pagos = SUM(p.monto)
        FROM mapUF m
        JOIN dbo.Pago p ON p.nroUnidadFuncional = m.idUF
        WHERE p.fechaPago <= @FechaCorte
        GROUP BY m.idPersona
    ),
    expe AS (
        SELECT m.idPersona, total_exp = SUM(e.montoTotal)
        FROM mapUF m
        JOIN dbo.Expensa e ON e.idUF = m.idUF
        WHERE e.periodo <= EOMONTH(@FechaCorte) -- ultimo dia del mes de fechaCorte
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
        LEFT JOIN expe x ON x.idPersona = m.idPersona
    )
    SELECT TOP (@TopN)
        nombre, apellido, dni, email, telefono,
        pagos, expen, deuda
    FROM base
    WHERE deuda > 0
    ORDER BY deuda DESC, apellido, nombre;
END
GO

/* 
   R6 — para cada uf, Fechas de pagos (ordinarios) por UF y días hasta el siguiente pago (XML)
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R6_PagosOrdinarios_XML
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL   -- NULL = todos
AS
BEGIN
    SET NOCOUNT ON;

    WITH pagos AS (
        SELECT uf.idUF, uf.numeroUnidad, c.nombre AS consorcio, p.fechaPago
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf  ON uf.idUF = p.nroUnidadFuncional
        JOIN dbo.Consorcio c  ON c.id = uf.idConsorcio -- este join se usa para filtrar por consorcio solamente 
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY, 1, @FechaHasta)        -- hasta @FechaHasta inclusive
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    )
    SELECT  -- agrupamos por UF
        idUF         AS [UF/@idUF],
        numeroUnidad AS [UF/@nro],
        consorcio    AS [UF/@consorcio],
        (
            SELECT
                p1.fechaPago AS [pago/@fecha],
                DATEDIFF(DAY,p1.fechaPago,LEAD(p1.fechaPago) OVER (PARTITION BY p1.idUF ORDER BY p1.fechaPago ) --obtenemos la fecha del proximo pago
                ) AS [pago/@dias_hasta_siguiente]
            FROM pagos p1
            WHERE p1.idUF = p.idUF
            ORDER BY p1.fechaPago
            FOR XML PATH(''), TYPE --genera los nodos
        )
    FROM pagos p
    GROUP BY idUF, numeroUnidad, consorcio
    ORDER BY consorcio, numeroUnidad
    FOR XML PATH(''), ROOT('PagosUF'), TYPE;
END
GO



