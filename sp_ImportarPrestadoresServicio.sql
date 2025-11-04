CREATE OR ALTER PROCEDURE dbo.sp_ImportarPrestadoresServicio
    @FilePath  NVARCHAR(4000),
    @SheetName SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#raw')   IS NOT NULL DROP TABLE #raw;
    IF OBJECT_ID('tempdb..#dedup') IS NOT NULL DROP TABLE #dedup;

    CREATE TABLE #raw (
        F1 NVARCHAR(4000),  -- tipoServicio
        F2 NVARCHAR(4000),  -- nombre
        F3 NVARCHAR(4000),  -- cuenta
        F4 NVARCHAR(4000)   -- nombre consorcio
    );

    DECLARE 
        @prov  NVARCHAR(200)  = N'Microsoft.ACE.OLEDB.16.0',
        @ext   NVARCHAR(4000) = N'Excel 12.0 Xml;HDR=NO;IMEX=1;Mode=Read;ReadOnly=1;Database=' + REPLACE(@FilePath,'''',''''''),
        @qry   NVARCHAR(MAX)  = N'SELECT F1,F2,F3,F4 FROM [' + REPLACE(@SheetName,'''','''''') + N'B3:E30]',
        @sql   NVARCHAR(MAX);

    SET @sql = N'
INSERT INTO #raw(F1,F2,F3,F4)
SELECT F1,F2,F3,F4
FROM OPENROWSET(''' + @prov + ''',''' + @ext + ''',''' + @qry + ''');';
    EXEC sys.sp_executesql @sql;

    CREATE TABLE #dedup
    (
        idConsorcio     INT          NOT NULL,
        tipoServicio    VARCHAR(100) NOT NULL,
        nombre          VARCHAR(100) NOT NULL,
        cuenta          VARCHAR(100) NULL
    );

    INSERT INTO #dedup (idConsorcio, tipoServicio, nombre, cuenta)
    SELECT idConsorcio, tipoServicio, nombre, cuenta
    FROM (
        SELECT
            c.id AS idConsorcio,
            tipoServicio = LEFT(LTRIM(RTRIM(r.F1)), 100),
            nombre       = LEFT(LTRIM(RTRIM(r.F2)), 100),
            cuenta = CASE 
                       WHEN TRY_CONVERT(BIGINT,
                             NULLIF(
                               REPLACE(REPLACE(REPLACE(LOWER(LTRIM(RTRIM(r.F3))), N'cuenta ', N''), ' ', ''), '.', ''),
                             '')
                         ) IS NOT NULL
                       THEN NULLIF(
                              REPLACE(REPLACE(REPLACE(LOWER(LTRIM(RTRIM(r.F3))), N'cuenta ', N''), ' ', ''), '.', ''),
                            '')
                       ELSE NULL
                     END,
            rn = ROW_NUMBER() OVER (
                    PARTITION BY c.id, 
                                 LEFT(LTRIM(RTRIM(r.F2)),100), 
                                 LEFT(LTRIM(RTRIM(r.F1)),100)
                    ORDER BY (SELECT 0)
                 )
        FROM #raw r
        JOIN dbo.Consorcio c
          ON c.nombre = LTRIM(RTRIM(r.F4))
        WHERE LTRIM(RTRIM(r.F1)) IS NOT NULL AND LTRIM(RTRIM(r.F1)) <> ''
          AND LTRIM(RTRIM(r.F2)) IS NOT NULL AND LTRIM(RTRIM(r.F2)) <> ''
    ) x
    WHERE rn = 1;

    UPDATE ps
       SET ps.cuenta = d.cuenta
    FROM dbo.PrestadorServicio ps
    JOIN #dedup d
      ON  d.idConsorcio  = ps.idConsorcio
      AND d.nombre       = ps.nombre
      AND d.tipoServicio = ps.tipoServicio;

    INSERT INTO dbo.PrestadorServicio (idConsorcio, nombre, tipoServicio, cuenta)
    SELECT d.idConsorcio, d.nombre, d.tipoServicio, d.cuenta
    FROM #dedup d
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.PrestadorServicio ps
        WHERE ps.idConsorcio  = d.idConsorcio
          AND ps.nombre       = d.nombre
          AND ps.tipoServicio = d.tipoServicio
    );
END
GO
