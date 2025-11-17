USE Com3900G02;
GO


CREATE OR ALTER PROCEDURE dbo.sp_GenerarFacturasYEstados
    @Anio          INT,
    @Mes           INT,
    @FechaEmision  DATE   -- fecha base para emisión y envío
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FechaInicioPeriodo DATE = DATEFROMPARTS(@Anio, @Mes, 1);
    DECLARE @FechaFinPeriodo    DATE = EOMONTH(@FechaInicioPeriodo);

    INSERT INTO dbo.FacturaExpensa (
        idExpensa,
        fechaEmision,
        fechaVencimiento,
        nroVencimiento,
        interesPorMora,
        totalGastoOrdinario,
        totalGastoExtraordinario
    )
    SELECT 
        e.id                                         AS idExpensa,
        @FechaEmision                                AS fechaEmision,
        DATEADD(DAY, 10, @FechaEmision)             AS fechaVencimiento,  -- ej: +10 días
        1                                            AS nroVencimiento,
        0                                            AS interesPorMora,
        SUM(CASE WHEN de.categoria = 'EXTRAORDINARIO' 
                 THEN 0 
                 ELSE de.importe 
            END) AS totalGastoOrdinario,
        SUM(CASE WHEN de.categoria = 'EXTRAORDINARIO'
                 THEN de.importe 
                 ELSE 0 
            END) AS totalGastoExtraordinario
    FROM dbo.Expensa e
    LEFT JOIN dbo.DetalleExpensa de 
           ON de.idExpensa = e.id
    WHERE e.periodo >= @FechaInicioPeriodo
      AND e.periodo <= @FechaFinPeriodo
      AND NOT EXISTS (
            SELECT 1
            FROM dbo.FacturaExpensa fe
            WHERE fe.idExpensa = e.id
          )
    GROUP BY e.id;

    IF OBJECT_ID('tempdb..#ExpensasPeriodo') IS NOT NULL
        DROP TABLE #ExpensasPeriodo;

    SELECT 
        e.id   AS idExpensa,
        e.idUF,
        e.periodo,
        e.montoTotal,
        fe.totalGastoOrdinario + fe.totalGastoExtraordinario AS totalFactura
    INTO #ExpensasPeriodo
    FROM dbo.Expensa e
    JOIN dbo.FacturaExpensa fe ON fe.idExpensa = e.id
    WHERE e.periodo >= @FechaInicioPeriodo
      AND e.periodo <= @FechaFinPeriodo;

    ;WITH ExpensasConSaldoAnterior AS (
        SELECT
            ep.*,
            ISNULL(prev.saldoTotal, 0) AS saldoAnterior
        FROM #ExpensasPeriodo ep
        OUTER APPLY (
            SELECT TOP (1) ef.saldoTotal
            FROM dbo.EstadoFinanciero ef
            JOIN dbo.Expensa exPrev ON exPrev.id = ef.idExpensa
            WHERE exPrev.idUF   = ep.idUF
              AND exPrev.periodo < ep.periodo
            ORDER BY exPrev.periodo DESC
        ) prev
    ),
    ExpensasConPagos AS (
        SELECT
            ep.*,
            (
                SELECT ISNULL(SUM(p.monto), 0)
                FROM dbo.Pago p
                WHERE p.nroUnidadFuncional = ep.idUF
                  AND p.fechaPago >= @FechaInicioPeriodo
                  AND p.fechaPago <= @FechaFinPeriodo
            ) AS pagosPeriodo
        FROM ExpensasConSaldoAnterior ep
    ),
    CalculosEstado AS (
        SELECT
            ep.idExpensa,
            ep.idUF,
            ep.periodo,
            ep.saldoAnterior,
            ep.montoTotal                        AS importeMes,
            ep.pagosPeriodo,
            CAST(ep.saldoAnterior 
                 + ep.montoTotal 
                 - ep.pagosPeriodo AS DECIMAL(10,2)) AS saldoNuevo
        FROM ExpensasConPagos ep
    )
    INSERT INTO dbo.EstadoFinanciero (
        idExpensa,
        saldoAnterior,
        saldoNuevo,
        saldoDeudor,
        saldoAdelantado,
        saldoTotal
    )
    SELECT
        c.idExpensa,
        c.saldoAnterior,
        c.saldoNuevo,
        CASE WHEN c.saldoNuevo > 0 THEN c.saldoNuevo ELSE 0 END AS saldoDeudor,
        CASE WHEN c.saldoNuevo < 0 THEN -c.saldoNuevo ELSE 0 END AS saldoAdelantado,
        c.saldoNuevo AS saldoTotal
    FROM CalculosEstado c
    WHERE NOT EXISTS (
        SELECT 1 
        FROM dbo.EstadoFinanciero ef 
        WHERE ef.idExpensa = c.idExpensa
    );

    UPDATE e
    SET e.fechaEnvio = x.fechaEnvio
    FROM dbo.Expensa e
    JOIN #ExpensasPeriodo ep
      ON ep.idExpensa = e.id
    CROSS APPLY (
        SELECT MIN(fechaPosible) AS fechaEnvio
        FROM (
             VALUES ( @FechaEmision ),
                    ( DATEADD(DAY, 1, @FechaEmision) ),
                    ( DATEADD(DAY, 2, @FechaEmision) ),
                    ( DATEADD(DAY, 3, @FechaEmision) ),
                    ( DATEADD(DAY, 4, @FechaEmision) ),
                    ( DATEADD(DAY, 5, @FechaEmision) ),
                    ( DATEADD(DAY, 6, @FechaEmision) ),
                    ( DATEADD(DAY, 7, @FechaEmision) ),
                    ( DATEADD(DAY, 8, @FechaEmision) ),
                    ( DATEADD(DAY, 9, @FechaEmision) ),
                    ( DATEADD(DAY,10, @FechaEmision) )
        ) AS fechas(fechaPosible)
        WHERE dbo.esFeriado(fechaPosible) = 0
    ) x;

    DROP TABLE #ExpensasPeriodo;
END;
GO


CREATE OR ALTER PROCEDURE dbo.CargarFeriados
    @anio INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @url NVARCHAR(64) = 
        N'https://api.argentinadatos.com/v1/feriados/' + CAST(@anio AS NVARCHAR(10));

    DECLARE @Object INT;
    DECLARE @json TABLE (respuesta NVARCHAR(MAX));
    DECLARE @respuesta NVARCHAR(MAX);

    -- Crear objeto OLE
    EXEC sp_OACreate 'MSXML2.XMLHTTP', @Object OUT;

    -- Hacer el GET
    EXEC sp_OAMethod @Object, 'OPEN', NULL, 'GET', @url, 'FALSE';
    EXEC sp_OAMethod @Object, 'SEND';
    EXEC sp_OAMethod @Object, 'RESPONSETEXT', @respuesta OUTPUT;

    -- Guardar RESPONSETEXT en la tabla
    INSERT INTO @json (respuesta)
        EXEC sp_OAGetProperty @Object, 'RESPONSETEXT';

    -- Destruir objeto
    EXEC sp_OADestroy @Object;

    -- Tomar el JSON final desde la tabla
    SELECT TOP (1) @respuesta = respuesta
    FROM @json;

    DELETE FROM dbo.Feriados
    WHERE YEAR(fecha) = @anio;

    INSERT INTO dbo.Feriados (fecha, tipo, nombre)
    SELECT
        CONVERT(date, JSON_VALUE(j.value, '$.fecha'))  AS fecha,
        JSON_VALUE(j.value, '$.tipo')                  AS tipo,
        JSON_VALUE(j.value, '$.nombre')                AS nombre
    FROM OPENJSON(@respuesta) AS j;
END;
GO
