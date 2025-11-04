USE Com3900G02;
GO

CREATE OR ALTER FUNCTION dbo.fnBuscarUnidadPorCBU
(
    @cbu_cvu VARCHAR(30)
)
RETURNS INT
AS
BEGIN
    DECLARE @numeroUnidad INT;

    SELECT @numeroUnidad = numeroUnidad
    FROM dbo.UnidadFuncional
    WHERE cbu_cvu_actual = @cbu_cvu;

    RETURN @numeroUnidad;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CargarPagosDesdeCsv
    @FilePath NVARCHAR(500)   -- ✅ Nuevo parámetro: ruta del archivo CSV
AS
BEGIN
    SET NOCOUNT ON;

    -- Elimina staging previo si existía
    IF OBJECT_ID('tempdb..#stg_pagos') IS NOT NULL DROP TABLE #stg_pagos;

    CREATE TABLE #stg_pagos
    (
        IdDePago  VARCHAR(100) NULL,
        FechaTxt  VARCHAR(50)  NULL,
        CbuCvu    VARCHAR(60)  NULL,
        ValorTxt  VARCHAR(100) NULL
    );

    -- BULK INSERT directo usando parámetro
    DECLARE @sql NVARCHAR(MAX);
    SET @sql = N'
        BULK INSERT #stg_pagos
        FROM ''' + REPLACE(@FilePath, '''', '''''') + N'''
        WITH (
            FIRSTROW = 2,                -- Saltea encabezado
            FIELDTERMINATOR = '','',     -- Separador de campos
            ROWTERMINATOR = ''\n'',      -- Fin de línea Windows (usar ''\n'' si no carga)
            DATAFILETYPE = ''char'',
            TABLOCK
        );
    ';
    EXEC sys.sp_executesql @sql;

    INSERT INTO dbo.Pago (FechaPago, cbu, Monto, idDePago, nroUnidadFuncional)
    SELECT
        COALESCE(TRY_CONVERT(date, FechaTxt, 103), TRY_CONVERT(date, FechaTxt)) AS FechaPago,
        REPLACE(CbuCvu, ' ', '') AS CbuCvu,
        REPLACE(REPLACE(REPLACE(ValorTxt, ' ', ''), '$', ''), '.', '') AS Monto,
        IdDePago,
        dbo.fnBuscarUnidadPorCBU(CbuCvu) AS nroUnidad
    FROM (
        SELECT s.IdDePago, s.FechaTxt, s.CbuCvu, s.ValorTxt
        FROM dbo.Pago p
        RIGHT JOIN #stg_pagos s ON p.idDePago = s.idDePago
        WHERE p.idDePago IS NULL
    ) AS result
    WHERE FechaTxt IS NOT NULL 
      AND CbuCvu IS NOT NULL 
      AND IdDePago IS NOT NULL 
      AND FechaTxt IS NOT NULL;
END;
GO