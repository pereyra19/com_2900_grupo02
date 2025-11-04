CREATE OR ALTER PROCEDURE dbo.sp_ImportacionServicios
    @FilePath NVARCHAR(4000),
    @Year     INT = 2025
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @json NVARCHAR(MAX);
    DECLARE @sql  NVARCHAR(MAX) =
       N'SELECT @out = CONVERT(NVARCHAR(MAX), BulkColumn)
         FROM OPENROWSET(BULK ' + QUOTENAME(@FilePath,'''') + N', SINGLE_CLOB) AS J;';
    EXEC sp_executesql @sql, N'@out NVARCHAR(MAX) OUTPUT', @out=@json OUTPUT;

    IF OBJECT_ID('tempdb..#cm') IS NOT NULL DROP TABLE #cm;
    CREATE TABLE #cm(
        consId           INT         NOT NULL,
        PeriodDate       DATE        NOT NULL,
        BancariosTotal   DECIMAL(12,2) NULL,
        LimpiezaTotal    DECIMAL(12,2) NULL,
        AdministracionTotal DECIMAL(12,2) NULL,
        SegurosTotal     DECIMAL(12,2) NULL,
        GastosGralesTotal DECIMAL(12,2) NULL,
        ServPubAguaTotal DECIMAL(12,2) NULL,
        ServPubLuzTotal  DECIMAL(12,2) NULL
    );

    INSERT INTO #cm(consId, PeriodDate, BancariosTotal, LimpiezaTotal, AdministracionTotal,
                    SegurosTotal, GastosGralesTotal, ServPubAguaTotal, ServPubLuzTotal)
    SELECT 
        c.id AS consId,
        DATEFROMPARTS(@Year,
            CASE LOWER(LTRIM(RTRIM(j.Mes)))
                WHEN 'enero' THEN 1  WHEN 'febrero' THEN 2  WHEN 'marzo' THEN 3
                WHEN 'abril' THEN 4  WHEN 'mayo'    THEN 5  WHEN 'junio' THEN 6
                WHEN 'julio' THEN 7  WHEN 'agosto'  THEN 8  WHEN 'septiembre' THEN 9
                WHEN 'octubre' THEN 10 WHEN 'noviembre' THEN 11 WHEN 'diciembre' THEN 12
            END, 1
        ) AS PeriodDate,
        TRY_CAST(CASE 
            WHEN CHARINDEX('.', j.BancariosRaw) > 0 AND CHARINDEX(',', j.BancariosRaw) = 0 THEN LTRIM(RTRIM(j.BancariosRaw))
            WHEN CHARINDEX('.', j.BancariosRaw) = 0 AND CHARINDEX(',', j.BancariosRaw) > 0 THEN REPLACE(LTRIM(RTRIM(j.BancariosRaw)), ',', '.')
            WHEN CHARINDEX('.', j.BancariosRaw) > CHARINDEX(',', j.BancariosRaw) THEN REPLACE(LTRIM(RTRIM(j.BancariosRaw)), ',', '')
            ELSE REPLACE(REPLACE(LTRIM(RTRIM(j.BancariosRaw)), '.', ''), ',', '.')
        END AS DECIMAL(12,2)) AS BancariosTotal,
        TRY_CAST(CASE 
            WHEN CHARINDEX('.', j.LimpiezaRaw) > 0 AND CHARINDEX(',', j.LimpiezaRaw) = 0 THEN LTRIM(RTRIM(j.LimpiezaRaw))
            WHEN CHARINDEX('.', j.LimpiezaRaw) = 0 AND CHARINDEX(',', j.LimpiezaRaw) > 0 THEN REPLACE(LTRIM(RTRIM(j.LimpiezaRaw)), ',', '.')
            WHEN CHARINDEX('.', j.LimpiezaRaw) > CHARINDEX(',', j.LimpiezaRaw) THEN REPLACE(LTRIM(RTRIM(j.LimpiezaRaw)), ',', '')
            ELSE REPLACE(REPLACE(LTRIM(RTRIM(j.LimpiezaRaw)), '.', ''), ',', '.')
        END AS DECIMAL(12,2)) AS LimpiezaTotal,
        TRY_CAST(CASE 
            WHEN CHARINDEX('.', j.AdministracionRaw) > 0 AND CHARINDEX(',', j.AdministracionRaw) = 0 THEN LTRIM(RTRIM(j.AdministracionRaw))
            WHEN CHARINDEX('.', j.AdministracionRaw) = 0 AND CHARINDEX(',', j.AdministracionRaw) > 0 THEN REPLACE(LTRIM(RTRIM(j.AdministracionRaw)), ',', '.')
            WHEN CHARINDEX('.', j.AdministracionRaw) > CHARINDEX(',', j.AdministracionRaw) THEN REPLACE(LTRIM(RTRIM(j.AdministracionRaw)), ',', '')
            ELSE REPLACE(REPLACE(LTRIM(RTRIM(j.AdministracionRaw)), '.', ''), ',', '.')
        END AS DECIMAL(12,2)) AS AdministracionTotal,
        TRY_CAST(CASE 
            WHEN CHARINDEX('.', j.SegurosRaw) > 0 AND CHARINDEX(',', j.SegurosRaw) = 0 THEN LTRIM(RTRIM(j.SegurosRaw))
            WHEN CHARINDEX('.', j.SegurosRaw) = 0 AND CHARINDEX(',', j.SegurosRaw) > 0 THEN REPLACE(LTRIM(RTRIM(j.SegurosRaw)), ',', '.')
            WHEN CHARINDEX('.', j.SegurosRaw) > CHARINDEX(',', j.SegurosRaw) THEN REPLACE(LTRIM(RTRIM(j.SegurosRaw)), ',', '')
            ELSE REPLACE(REPLACE(LTRIM(RTRIM(j.SegurosRaw)), '.', ''), ',', '.')
        END AS DECIMAL(12,2)) AS SegurosTotal,
        TRY_CAST(CASE 
            WHEN CHARINDEX('.', j.GastosGralesRaw) > 0 AND CHARINDEX(',', j.GastosGralesRaw) = 0 THEN LTRIM(RTRIM(j.GastosGralesRaw))
            WHEN CHARINDEX('.', j.GastosGralesRaw) = 0 AND CHARINDEX(',', j.GastosGralesRaw) > 0 THEN REPLACE(LTRIM(RTRIM(j.GastosGralesRaw)), ',', '.')
            WHEN CHARINDEX('.', j.GastosGralesRaw) > CHARINDEX(',', j.GastosGralesRaw) THEN REPLACE(LTRIM(RTRIM(j.GastosGralesRaw)), ',', '')
            ELSE REPLACE(REPLACE(LTRIM(RTRIM(j.GastosGralesRaw)), '.', ''), ',', '.')
        END AS DECIMAL(12,2)) AS GastosGralesTotal,
        TRY_CAST(CASE 
            WHEN CHARINDEX('.', j.ServPubAguaRaw) > 0 AND CHARINDEX(',', j.ServPubAguaRaw) = 0 THEN LTRIM(RTRIM(j.ServPubAguaRaw))
            WHEN CHARINDEX('.', j.ServPubAguaRaw) = 0 AND CHARINDEX(',', j.ServPubAguaRaw) > 0 THEN REPLACE(LTRIM(RTRIM(j.ServPubAguaRaw)), ',', '.')
            WHEN CHARINDEX('.', j.ServPubAguaRaw) > CHARINDEX(',', j.ServPubAguaRaw) THEN REPLACE(LTRIM(RTRIM(j.ServPubAguaRaw)), ',', '')
            ELSE REPLACE(REPLACE(LTRIM(RTRIM(j.ServPubAguaRaw)), '.', ''), ',', '.')
        END AS DECIMAL(12,2)) AS ServPubAguaTotal,
        TRY_CAST(CASE 
            WHEN CHARINDEX('.', j.ServPubLuzRaw) > 0 AND CHARINDEX(',', j.ServPubLuzRaw) = 0 THEN LTRIM(RTRIM(j.ServPubLuzRaw))
            WHEN CHARINDEX('.', j.ServPubLuzRaw) = 0 AND CHARINDEX(',', j.ServPubLuzRaw) > 0 THEN REPLACE(LTRIM(RTRIM(j.ServPubLuzRaw)), ',', '.')
            WHEN CHARINDEX('.', j.ServPubLuzRaw) > CHARINDEX(',', j.ServPubLuzRaw) THEN REPLACE(LTRIM(RTRIM(j.ServPubLuzRaw)), ',', '')
            ELSE REPLACE(REPLACE(LTRIM(RTRIM(j.ServPubLuzRaw)), '.', ''), ',', '.')
        END AS DECIMAL(12,2)) AS ServPubLuzTotal
    FROM OPENJSON(@json) WITH (
        NameConsorcio      NVARCHAR(100) '$."Nombre del consorcio"',
        Mes                NVARCHAR(50)  '$.Mes',
        BancariosRaw       NVARCHAR(50)  '$.BANCARIOS',
        LimpiezaRaw        NVARCHAR(50)  '$.LIMPIEZA',
        AdministracionRaw  NVARCHAR(50)  '$.ADMINISTRACION',
        SegurosRaw         NVARCHAR(50)  '$.SEGUROS',
        GastosGralesRaw    NVARCHAR(50)  '$."GASTOS GENERALES"',
        ServPubAguaRaw     NVARCHAR(50)  '$."SERVICIOS PUBLICOS-Agua"',
        ServPubLuzRaw      NVARCHAR(50)  '$."SERVICIOS PUBLICOS-Luz"'
    ) AS j
    JOIN dbo.Consorcio c ON c.nombre = LTRIM(RTRIM(j.NameConsorcio));

    IF OBJECT_ID('tempdb..#expUF') IS NOT NULL DROP TABLE #expUF;
    CREATE TABLE #expUF(
        idUF       INT         NOT NULL,
        PeriodDate DATE        NOT NULL,
        MontoTotal DECIMAL(12,2) NOT NULL
    );

    INSERT INTO #expUF(idUF, PeriodDate, MontoTotal)
    SELECT 
        uf.idUF,
        cm.PeriodDate,
          ROUND(COALESCE(cm.BancariosTotal,0)       * uf.coeficiente/100, 2)
        + ROUND(COALESCE(cm.LimpiezaTotal,0)        * uf.coeficiente/100, 2)
        + ROUND(COALESCE(cm.AdministracionTotal,0)  * uf.coeficiente/100, 2)
        + ROUND(COALESCE(cm.SegurosTotal,0)         * uf.coeficiente/100, 2)
        + ROUND(COALESCE(cm.GastosGralesTotal,0)    * uf.coeficiente/100, 2)
        + ROUND(COALESCE(cm.ServPubAguaTotal,0)     * uf.coeficiente/100, 2)
        + ROUND(COALESCE(cm.ServPubLuzTotal,0)      * uf.coeficiente/100, 2) AS MontoTotal
    FROM #cm cm
    JOIN dbo.UnidadFuncional uf ON uf.idConsorcio = cm.consId;

    IF OBJECT_ID('tempdb..#detUF') IS NOT NULL DROP TABLE #detUF;
    CREATE TABLE #detUF(
        idUF       INT          NOT NULL,
        PeriodDate DATE         NOT NULL,
        Concepto   NVARCHAR(80) NOT NULL,
        Importe    DECIMAL(12,2) NOT NULL
    );

    INSERT INTO #detUF(idUF, PeriodDate, Concepto, Importe)
    SELECT 
        uf.idUF,
        cm.PeriodDate,
        x.Concepto,
        x.Importe
    FROM #cm cm
    JOIN dbo.UnidadFuncional uf ON uf.idConsorcio = cm.consId
    CROSS APPLY (VALUES
        (N'BANCARIOS'             , ROUND(COALESCE(cm.BancariosTotal,0)      * uf.coeficiente/100, 2)),
        (N'LIMPIEZA'              , ROUND(COALESCE(cm.LimpiezaTotal,0)       * uf.coeficiente/100, 2)),
        (N'ADMINISTRACION'        , ROUND(COALESCE(cm.AdministracionTotal,0) * uf.coeficiente/100, 2)),
        (N'SEGUROS'               , ROUND(COALESCE(cm.SegurosTotal,0)        * uf.coeficiente/100, 2)),
        (N'GASTOS GENERALES'      , ROUND(COALESCE(cm.GastosGralesTotal,0)   * uf.coeficiente/100, 2)),
        (N'SERVICIOS PUBLICOS-Agua', ROUND(COALESCE(cm.ServPubAguaTotal,0)   * uf.coeficiente/100, 2)),
        (N'SERVICIOS PUBLICOS-Luz' , ROUND(COALESCE(cm.ServPubLuzTotal,0)    * uf.coeficiente/100, 2))
    ) AS x(Concepto, Importe)
    WHERE x.Importe > 0;


    DECLARE @NewExpensas TABLE(idExpensa INT, idUF INT, Periodo DATE);
    INSERT INTO dbo.Expensa (idUF, periodo, montoTotal)
    OUTPUT inserted.id, inserted.idUF, inserted.periodo INTO @NewExpensas(idExpensa, idUF, Periodo)
    SELECT e.idUF, e.PeriodDate, e.MontoTotal
    FROM #expUF e;

    INSERT INTO dbo.DetalleExpensa (idExpensa, idPrestadorServicio, importe, nroFactura, tipo, categoria, nroCuota)
    SELECT 
        ne.idExpensa,
        ps.id AS idPrestadorServicio,
        d.Importe,
        NULL, NULL, NULL, NULL
    FROM @NewExpensas ne
    JOIN #detUF d
      ON d.idUF = ne.idUF AND d.PeriodDate = ne.Periodo
    JOIN dbo.UnidadFuncional uf
      ON uf.idUF = ne.idUF
    JOIN dbo.PrestadorServicio ps
      ON ps.idConsorcio = uf.idConsorcio
     AND ps.tipoServicio = d.Concepto;  -- mapea concepto->tipoServicio

END
GO
