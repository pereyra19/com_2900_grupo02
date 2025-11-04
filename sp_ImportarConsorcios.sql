CREATE OR ALTER PROCEDURE dbo.sp_ImportarConsorcios
    @FilePath  NVARCHAR(4000),
    @SheetName SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#raw')   IS NOT NULL DROP TABLE #raw;
    IF OBJECT_ID('tempdb..#dedup') IS NOT NULL DROP TABLE #dedup;

    CREATE TABLE #raw
    (
        [Consorcio]                   NVARCHAR(255) NULL,
        [Nombre del consorcio]        NVARCHAR(255) NULL,
        [Domicilio]                   NVARCHAR(255) NULL,
        [Cant unidades funcionales]   NVARCHAR(255) NULL,
        [m2 totales]                  NVARCHAR(255) NULL
    );

    DECLARE 
        @prov  NVARCHAR(200)  = N'Microsoft.ACE.OLEDB.16.0',
        @ext   NVARCHAR(4000) = N'Excel 12.0 Xml;HDR=YES;IMEX=1;Mode=Read;ReadOnly=1;Database=' + @FilePath,
        @sheet NVARCHAR(300)  = N'[' + REPLACE(@SheetName, '''', '''''') + N']',
        @sql   NVARCHAR(MAX);

    SET @sql = N'
INSERT INTO #raw ([Consorcio],[Nombre del consorcio],[Domicilio],[Cant unidades funcionales],[m2 totales])
SELECT [Consorcio],[Nombre del consorcio],[Domicilio],[Cant unidades funcionales],[m2 totales]
FROM OPENROWSET(''' + @prov + ''',''' + @ext + ''',
     ''SELECT [Consorcio],[Nombre del consorcio],[Domicilio],[Cant unidades funcionales],[m2 totales]
       FROM ' + @sheet + '''
);';
    EXEC sys.sp_executesql @sql;

    CREATE TABLE #dedup
    (
        nombre           VARCHAR(100) NOT NULL,
        domicilio        VARCHAR(100) NOT NULL,
        cantidadUnidades INT          NOT NULL,
        m2totales        INT          NOT NULL
    );

    INSERT INTO #dedup (nombre, domicilio, cantidadUnidades, m2totales)
    SELECT nombre, domicilio, cantidadUnidades, m2totales
    FROM (
        SELECT
            nombre           = LEFT(LTRIM(RTRIM([Nombre del consorcio])), 100),
            domicilio        = LEFT(LTRIM(RTRIM([Domicilio])), 100),
            cantidadUnidades = TRY_CAST(REPLACE(REPLACE([Cant unidades funcionales],'.',''),',','') AS INT),
            m2totales        = TRY_CAST(REPLACE(REPLACE([m2 totales],'.',''),',','') AS INT),
            rn = ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM([Nombre del consorcio])) ORDER BY (SELECT 0))
        FROM #raw
    ) x
    WHERE
        rn = 1
        AND nombre           IS NOT NULL AND nombre    <> ''
        AND domicilio        IS NOT NULL AND domicilio <> ''
        AND cantidadUnidades IS NOT NULL AND cantidadUnidades > 0
        AND m2totales        IS NOT NULL AND m2totales        > 0;

    -- UPDATE por nombre
    UPDATE c
       SET c.domicilio        = d.domicilio,
           c.cantidadUnidades = d.cantidadUnidades,
           c.m2totales        = d.m2totales
    FROM dbo.Consorcio c
    JOIN #dedup d ON d.nombre = c.nombre;

    -- INSERT de los que no existen
    INSERT INTO dbo.Consorcio (nombre, domicilio, cantidadUnidades, m2totales)
    SELECT d.nombre, d.domicilio, d.cantidadUnidades, d.m2totales
    FROM #dedup d
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Consorcio c WHERE c.nombre = d.nombre);
END
GO
