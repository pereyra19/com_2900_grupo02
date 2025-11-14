
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

    DECLARE @Base date = '20010101'; -- lunes cualquiera para calcular semanas.

    WITH pagos AS ( -- registro por pago (via JOIN unidadFuncional)
        SELECT
            p.id,
            p.fechaPago,
            p.monto,
            uf.idConsorcio,
            -- Si no hay algún detalle/categoría → se considera ordinario
            esExtra = CASE WHEN EXISTS (
                          SELECT 1
                          FROM dbo.PagoExpensa pe -- MAL -------------------------------------------------
                          JOIN dbo.DetalleExpensa d ON d.idExpensa = pe.idExpensa
                          WHERE pe.idPago = p.id
                            AND (d.categoria LIKE '%extra%' OR d.tipo LIKE '%extra%') ------------------------ ? 
                       ) THEN 1 ELSE 0 END
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
        WHERE p.fechaPago >= @FechaDesde -- limpiamos por rango de fechas y por consorcio (en caso que no sea NULL)
          AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    ),
    sem AS (
        SELECT -- selecionamos pagos por inicio de semana
            semana_ini = DATEADD(WEEK, DATEDIFF(WEEK, @Base, fechaPago), @Base),
            -- Sumamos por semana 
            rec_ordi   = SUM(CASE WHEN esExtra = 0 THEN monto ELSE 0 END),
            rec_extra  = SUM(CASE WHEN esExtra = 1 THEN monto ELSE 0 END)
        FROM pagos
        GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, @Base, fechaPago), @Base)
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

/* 
   R2 — Recaudación por MES y DEPARTAMENTO (PIVOT DINÁMICO) en XML
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R2_RecaudacionMesDepto_XML
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL      -- NULL = todos
AS
BEGIN
    SET NOCOUNT ON;

    /* armamos la lista de columnas [YYYY-MM] presentes en el rango */
    DECLARE @cols nvarchar(max);

    WITH meses AS (
        SELECT DISTINCT
            mes_key = CONVERT(char(7), DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1), 126)
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
    )
    SELECT @cols = STRING_AGG(QUOTENAME(mes_key), ',') WITHIN GROUP (ORDER BY mes_key) --@cols = [2025-01],[2025-02]
    FROM meses;

    IF @cols IS NULL
    BEGIN
        -- sin datos → XML vacío 
        SELECT CAST('<RecaudacionMesDepto/>' AS xml) AS XMLResult;
        RETURN;
    END

    DECLARE @sql nvarchar(max) = N'
     WITH base AS (
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

    EXEC sp_executesql @sql, --se le pasa los valores al sql dinamico como parámetros
        N'@FechaDesde date, @FechaHasta date, @IdConsorcio int',
        @FechaDesde, @FechaHasta, @IdConsorcio;
END
GO

/*
   R3 — Cuadro cruzado de recaudación por procedencia 
         (periodo = mes; columnas = Ordinario/Extraordinario)
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R3_RecaudacionPorProcedencia
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    WITH base AS (
        SELECT
            mes = DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1),
            procedencia = CASE WHEN EXISTS ( --si tipo/categoria tiene datos va a "Extraordinario, si no "Ordinario".
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
          AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta) -- limpiamos por rango de fechas y por consorcio (en caso que no sea NULL)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio) -- 
    ),
    agg AS ( --sumamos por mes y procedencia 
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

/*
   R4 — Top 5 meses de MAYORES GASTOS y de MAYORES INGRESOS (TABULAR)
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R4_Top5Meses_GastosIngresos
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- DATEFROMPARTS arma los campor del DATE
    DECLARE @d1 date = DATEFROMPARTS(YEAR(@FechaDesde), MONTH(@FechaDesde), 1); -- primer dia del mes de fechaDesde
    -- DATEADD -> le suma 1 mes a la fechaHasta 
    DECLARE @d2 date = DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(@FechaHasta), MONTH(@FechaHasta), 1)); -- primer dia del mes siguiente

    WITH ing AS ( -- agrupamos por mes de fechaPago y suma el monto
        SELECT mes = DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1),
               total = SUM(p.monto)
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional -- filtamos consorcio a UF
        WHERE p.fechaPago >= @FechaDesde AND p.fechaPago < DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio=@IdConsorcio)
        GROUP BY DATEFROMPARTS(YEAR(p.fechaPago), MONTH(p.fechaPago), 1)
    ),
    gas AS ( -- suma detalleExpensa.importe por mes 
        SELECT mes = DATEFROMPARTS(YEAR(e.periodo), MONTH(e.periodo), 1), 
               total = SUM(d.importe)
        FROM dbo.DetalleExpensa d
        JOIN dbo.Expensa e          ON e.id = d.idExpensa
        JOIN dbo.UnidadFuncional uf ON uf.idUF = e.idUF
        WHERE e.periodo >= @d1 AND e.periodo < @d2
          AND (@IdConsorcio IS NULL OR uf.idConsorcio=@IdConsorcio)
        GROUP BY DATEFROMPARTS(YEAR(e.periodo), MONTH(e.periodo), 1)
    )
    SELECT TOP 5 'INGRESOS' AS tipo, mes, total -- devuelve ingresos 
    FROM ing
    ORDER BY total DESC, mes DESC;

    SELECT TOP 5 'GASTOS' AS tipo, mes, total -- devuelve gastos
    FROM gas
    ORDER BY total DESC, mes DESC;
END
GO

/* 
   R5 — Top N propietarios con mayor morosidad  ( se puede cambiar )
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R5_TopMorosos
    @FechaCorte  date,
    @IdConsorcio int = NULL,
    @TopN        int = 3
AS
BEGIN
    SET NOCOUNT ON;

    WITH mapUF AS (
        -- Vinculación Persona ↔ UF por CBU
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

/* 
   R6 — para cada uf, Fechas de pagos (ordinarios) por UF y días hasta el siguiente pago (XML)
*/
CREATE OR ALTER PROCEDURE dbo.rpt_R6_PagosOrdinarios_XML
    @FechaDesde  date,
    @FechaHasta  date,
    @IdConsorcio int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    WITH pagos AS (
        SELECT
            uf.idUF, uf.numeroUnidad, c.nombre AS consorcio, p.fechaPago
        FROM dbo.Pago p
        JOIN dbo.UnidadFuncional uf ON uf.idUF = p.nroUnidadFuncional
        JOIN dbo.Consorcio c        ON c.id = uf.idConsorcio
        WHERE p.fechaPago >= @FechaDesde
          AND p.fechaPago <  DATEADD(DAY,1,@FechaHasta)
          AND (@IdConsorcio IS NULL OR uf.idConsorcio = @IdConsorcio)
          -- filtro a "ordinarias" si hay marca de extra en el pago lo excluimos
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.PagoExpensa pe
                JOIN dbo.DetalleExpensa d ON d.idExpensa = pe.idExpensa
                WHERE pe.idPago = p.id
                  AND (d.categoria LIKE '%extra%' OR d.tipo LIKE '%extra%')
          )
    )
    SELECT -- agrupamos por UF 
      idUF         AS [UF/@idUF],
      numeroUnidad AS [UF/@nro],
      consorcio    AS [UF/@consorcio],
      (
        SELECT -- lista ordenada de pagos ordinarios
           p1.fechaPago                         AS [pago/@fecha],
           DATEDIFF(DAY, p1.fechaPago, 
                    LEAD(p1.fechaPago) OVER (PARTITION BY p1.idUF ORDER BY p1.fechaPago)) --obtenemos la fecha del proximo pago
                    AS [pago/@dias_hasta_siguiente] 
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




















