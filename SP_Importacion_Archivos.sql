-----------------------------------------------------------------------------------
-- SI creaste las tablas recién, apreta (f5) para refrescar la base 
-----------------------------------------------------------------------------------

USE Com3900G02;
GO

-- borrado de SP 
IF OBJECT_ID(N'dbo.SP_ImportarInquilinoPropietariosDatosCSV', N'P') IS NOT NULL DROP PROCEDURE dbo.SP_ImportarInquilinoPropietariosDatosCSV;
GO
IF OBJECT_ID(N'dbo.sp_ImportacionServicios', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_ImportacionServicios;
GO
IF OBJECT_ID(N'dbo.sp_Pagos_ImportarCSV', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_Pagos_ImportarCSV;
GO
IF OBJECT_ID(N'dbo.sp_ImportarConsorcios', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_ImportarConsorcios;
GO
IF OBJECT_ID(N'dbo.sp_ImportarPrestadoresServicio', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_ImportarPrestadoresServicio;
GO
IF OBJECT_ID(N'dbo.sp_ImportarInquilinoPropietariosUFCSV', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_ImportarInquilinoPropietariosUFCSV;
GO
IF OBJECT_ID(N'dbo.sp_Importar_UF_por_consorcio', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_Importar_UF_por_consorcio;
GO


--#01  sp_ImportacionServicios (JSON)
USE Com3900G02;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ImportacionServicios
    @RutaArchivo NVARCHAR(4000),
    @Anio        INT = 2025
AS
BEGIN
    SET NOCOUNT ON;

    --------------------------------------------------------------------
    -- 1) Leer el JSON del archivo a una variable
    --------------------------------------------------------------------
    DECLARE @jsonTexto NVARCHAR(MAX);
    DECLARE @sqlLeerArchivo NVARCHAR(MAX) =
        N'SELECT @salida = CONVERT(NVARCHAR(MAX), BulkColumn)
          FROM OPENROWSET(BULK ' + QUOTENAME(@RutaArchivo,'''') + N', SINGLE_CLOB) AS J;';

    EXEC sp_executesql @sqlLeerArchivo,
                       N'@salida NVARCHAR(MAX) OUTPUT',
                       @salida = @jsonTexto OUTPUT;

    --------------------------------------------------------------------
    -- 2) Tabla temporal con totales por consorcio y mes (#TotalesConsorcio)
    --------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#TotalesConsorcio') IS NOT NULL DROP TABLE #TotalesConsorcio;

    CREATE TABLE #TotalesConsorcio(
        idConsorcio        INT,
        periodo            DATE,
        totalBancarios     DECIMAL(12,2),
        totalLimpieza      DECIMAL(12,2),
        totalAdministracion DECIMAL(12,2),
        totalSeguros       DECIMAL(12,2),
        totalGastosGrales  DECIMAL(12,2),
        totalAgua          DECIMAL(12,2),
        totalLuz           DECIMAL(12,2)
    );

    INSERT INTO #TotalesConsorcio
        (idConsorcio, periodo,
         totalBancarios, totalLimpieza, totalAdministracion,
         totalSeguros, totalGastosGrales, totalAgua, totalLuz)
    SELECT 
        c.id AS idConsorcio,
        DATEFROMPARTS(@Anio,
            CASE LOWER(LTRIM(RTRIM(j.Mes)))
                WHEN 'enero' THEN 1 WHEN 'febrero' THEN 2 WHEN 'marzo' THEN 3
                WHEN 'abril' THEN 4 WHEN 'mayo' THEN 5 WHEN 'junio' THEN 6
                WHEN 'julio' THEN 7 WHEN 'agosto' THEN 8 WHEN 'septiembre' THEN 9
                WHEN 'octubre' THEN 10 WHEN 'noviembre' THEN 11 WHEN 'diciembre' THEN 12
            END, 1) AS periodo,
        dbo.fn_NormalizarImporte(j.BANCARIOS),
        dbo.fn_NormalizarImporte(j.LIMPIEZA),
        dbo.fn_NormalizarImporte(j.ADMINISTRACION),
        dbo.fn_NormalizarImporte(j.SEGUROS),
        dbo.fn_NormalizarImporte(j.[GASTOS GENERALES]),
        dbo.fn_NormalizarImporte(j.[SERVICIOS PUBLICOS-Agua]),
        dbo.fn_NormalizarImporte(j.[SERVICIOS PUBLICOS-Luz])
    FROM OPENJSON(@jsonTexto) WITH (
        [NombreConsorcio]          NVARCHAR(100) '$."Nombre del consorcio"',
        Mes                        NVARCHAR(50)  '$.Mes',
        BANCARIOS                  NVARCHAR(50)  '$.BANCARIOS',
        LIMPIEZA                   NVARCHAR(50)  '$.LIMPIEZA',
        ADMINISTRACION             NVARCHAR(50)  '$.ADMINISTRACION',
        SEGUROS                    NVARCHAR(50)  '$.SEGUROS',
        [GASTOS GENERALES]         NVARCHAR(50)  '$."GASTOS GENERALES"',
        [SERVICIOS PUBLICOS-Agua]  NVARCHAR(50)  '$."SERVICIOS PUBLICOS-Agua"',
        [SERVICIOS PUBLICOS-Luz]   NVARCHAR(50)  '$."SERVICIOS PUBLICOS-Luz"'
    ) AS j
    JOIN dbo.Consorcio c
      ON c.nombre = j.NombreConsorcio;

    --------------------------------------------------------------------
    -- 3) Calcular cuánto paga cada UF (#TotalesUF) según m2_UF + accesorios
    --------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#TotalesUF') IS NOT NULL DROP TABLE #TotalesUF;

    CREATE TABLE #TotalesUF(
        idUF     INT,
        periodo  DATE,
        montoUF  DECIMAL(12,2)
    );

    ;WITH AreaPorUF AS (
        SELECT uf.idUF,
               uf.idConsorcio,
               uf.m2_UF + COALESCE(SUM(ua.m2_baulera + ua.m2_cochera),0) AS m2TotalUF
        FROM dbo.UnidadFuncional uf
        LEFT JOIN dbo.UnidadAccesoria ua
          ON ua.idUnidadFuncional = uf.idUF
        GROUP BY uf.idUF, uf.idConsorcio, uf.m2_UF
    ),
    AreaTotalConsorcio AS (
        SELECT idConsorcio,
               SUM(m2TotalUF) AS m2TotalConsorcio
        FROM AreaPorUF
        GROUP BY idConsorcio
    ),
    CoeficienteFinal AS (
        SELECT a.idUF,
               a.idConsorcio,
               CASE 
                   WHEN t.m2TotalConsorcio = 0 THEN 0
                   ELSE (a.m2TotalUF * 100.0 / t.m2TotalConsorcio)
               END AS coefPorcentaje
        FROM AreaPorUF a
        JOIN AreaTotalConsorcio t
          ON t.idConsorcio = a.idConsorcio
    )
    INSERT INTO #TotalesUF(idUF, periodo, montoUF)
    SELECT uf.idUF,
           tc.periodo,
             ROUND(COALESCE(tc.totalBancarios,0)     * cf.coefPorcentaje/100, 2)
           + ROUND(COALESCE(tc.totalLimpieza,0)      * cf.coefPorcentaje/100, 2)
           + ROUND(COALESCE(tc.totalAdministracion,0)* cf.coefPorcentaje/100, 2)
           + ROUND(COALESCE(tc.totalSeguros,0)       * cf.coefPorcentaje/100, 2)
           + ROUND(COALESCE(tc.totalGastosGrales,0)  * cf.coefPorcentaje/100, 2)
           + ROUND(COALESCE(tc.totalAgua,0)          * cf.coefPorcentaje/100, 2)
           + ROUND(COALESCE(tc.totalLuz,0)           * cf.coefPorcentaje/100, 2)
    FROM #TotalesConsorcio tc
    JOIN dbo.UnidadFuncional uf
      ON uf.idConsorcio = tc.idConsorcio
    JOIN CoeficienteFinal cf
      ON cf.idUF = uf.idUF;

    --------------------------------------------------------------------
    -- 4) Detalle por concepto para cada UF (#DetalleUF)
    --------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#DetalleUF') IS NOT NULL DROP TABLE #DetalleUF;

    CREATE TABLE #DetalleUF(
        idUF     INT,
        periodo  DATE,
        concepto NVARCHAR(80),
        importe  DECIMAL(12,2)
    );

    ;WITH AreaPorUF AS (
        SELECT uf.idUF,
               uf.idConsorcio,
               uf.m2_UF + COALESCE(SUM(ua.m2_baulera + ua.m2_cochera),0) AS m2TotalUF
        FROM dbo.UnidadFuncional uf
        LEFT JOIN dbo.UnidadAccesoria ua
          ON ua.idUnidadFuncional = uf.idUF
        GROUP BY uf.idUF, uf.idConsorcio, uf.m2_UF
    ),
    AreaTotalConsorcio AS (
        SELECT idConsorcio,
               SUM(m2TotalUF) AS m2TotalConsorcio
        FROM AreaPorUF
        GROUP BY idConsorcio
    ),
    CoeficienteFinal AS (
        SELECT a.idUF,
               a.idConsorcio,
               CASE 
                   WHEN t.m2TotalConsorcio = 0 THEN 0
                   ELSE (a.m2TotalUF * 100.0 / t.m2TotalConsorcio)
               END AS coefPorcentaje
        FROM AreaPorUF a
        JOIN AreaTotalConsorcio t
          ON t.idConsorcio = a.idConsorcio
    )
    INSERT INTO #DetalleUF(idUF, periodo, concepto, importe)
    SELECT uf.idUF,
           tc.periodo,
           x.Concepto,
           x.Importe
    FROM #TotalesConsorcio tc
    JOIN dbo.UnidadFuncional uf
      ON uf.idConsorcio = tc.idConsorcio
    JOIN CoeficienteFinal cf
      ON cf.idUF = uf.idUF
    CROSS APPLY (VALUES
        ('BANCARIOS'              , ROUND(COALESCE(tc.totalBancarios,0)     * cf.coefPorcentaje/100, 2)),
        ('LIMPIEZA'               , ROUND(COALESCE(tc.totalLimpieza,0)      * cf.coefPorcentaje/100, 2)),
        ('ADMINISTRACION'         , ROUND(COALESCE(tc.totalAdministracion,0)* cf.coefPorcentaje/100, 2)),
        ('SEGUROS'                , ROUND(COALESCE(tc.totalSeguros,0)       * cf.coefPorcentaje/100, 2)),
        ('GASTOS GENERALES'       , ROUND(COALESCE(tc.totalGastosGrales,0)  * cf.coefPorcentaje/100, 2)),
        ('SERVICIOS PUBLICOS-Agua', ROUND(COALESCE(tc.totalAgua,0)          * cf.coefPorcentaje/100, 2)),
        ('SERVICIOS PUBLICOS-Luz' , ROUND(COALESCE(tc.totalLuz,0)           * cf.coefPorcentaje/100, 2))
    ) AS x(Concepto, Importe)
    WHERE x.Importe > 0;

    --------------------------------------------------------------------
    -- 5) Insertar Expensas (una por UF/periodo, sin duplicar)
    --------------------------------------------------------------------
    DECLARE @NuevasExpensas TABLE(idExpensa INT, idUF INT, periodo DATE);

    INSERT INTO dbo.Expensa (idUF, periodo, montoTotal)
    OUTPUT inserted.id, inserted.idUF, inserted.periodo
           INTO @NuevasExpensas(idExpensa, idUF, periodo)
    SELECT t.idUF, t.periodo, t.montoUF
    FROM #TotalesUF t
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Expensa e
        WHERE e.idUF = t.idUF
          AND e.periodo = t.periodo
    );

    --------------------------------------------------------------------
    -- 6) Insertar DetalleExpensa con tipo + categoría
    --    y matchear con PrestadorServicio usando el mapeo de conceptos
    --------------------------------------------------------------------
    INSERT INTO dbo.DetalleExpensa
        (idExpensa, idPrestadorServicio, importe, nroFactura, tipo, categoria, nroCuota)
    SELECT 
        ne.idExpensa,
        ps.id AS idPrestadorServicio,
        d.importe,
        NULL AS nroFactura,
        dbo.fn_MapearConceptoTipoServicio(d.concepto)   AS tipo,
        dbo.fn_MapearConceptoCategoria(d.concepto)      AS categoria,
        NULL AS nroCuota
    FROM @NuevasExpensas ne
    JOIN #DetalleUF d
      ON d.idUF    = ne.idUF
     AND d.periodo = ne.periodo
    JOIN dbo.UnidadFuncional uf
      ON uf.idUF = ne.idUF
    JOIN dbo.PrestadorServicio ps
      ON ps.idConsorcio  = uf.idConsorcio
     AND ps.tipoServicio = dbo.fn_MapearConceptoTipoServicio(d.concepto);

END;
GO


--#02 sp_CargarPagosDesdeCsv (CSV)

CREATE OR ALTER PROCEDURE dbo.sp_Pagos_ImportarCSV
    @FilePath NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#stg_pagos') IS NOT NULL DROP TABLE #stg_pagos;

    CREATE TABLE #stg_pagos
    (
        IdDePago  VARCHAR(100) NULL,
        FechaTxt  VARCHAR(50)  NULL,
        CbuCvu    VARCHAR(60)  NULL,
        ValorTxt  VARCHAR(100) NULL
    );

    DECLARE @sql NVARCHAR(MAX) = N'
        BULK INSERT #stg_pagos
        FROM ' + QUOTENAME(@FilePath,'''') + N'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = '','',
            ROWTERMINATOR   = ''0x0d0a'',
            DATAFILETYPE    = ''char'',
            TABLOCK
        );
    ';
    EXEC sys.sp_executesql @sql;

    INSERT INTO dbo.Pago (fechaPago, cbu, monto, idDePago, nroUnidadFuncional)
    SELECT
        COALESCE(TRY_CONVERT(date, s.FechaTxt, 103), TRY_CONVERT(date, s.FechaTxt)),
        REPLACE(s.CbuCvu, ' ', ''),
        REPLACE(REPLACE(REPLACE(s.ValorTxt, ' ', ''), '$', ''), '.', ''),
        s.IdDePago,
        uf.idUF
    FROM (
        SELECT s.IdDePago, s.FechaTxt, s.CbuCvu, s.ValorTxt
        FROM dbo.Pago p
        RIGHT JOIN #stg_pagos s ON p.idDePago = s.idDePago
        WHERE p.idDePago IS NULL
    ) AS s
    LEFT JOIN dbo.UnidadFuncional uf
      ON uf.cbu_cvu_actual = REPLACE(s.CbuCvu, ' ', '')
    WHERE s.FechaTxt IS NOT NULL 
      AND s.CbuCvu  IS NOT NULL 
      AND s.IdDePago IS NOT NULL
       AND uf.idUF IS NOT NULL;
END;
GO



-- #03  sp_ImportarConsorcios (XLSX)

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

    UPDATE c
       SET c.domicilio        = d.domicilio,
           c.cantidadUnidades = d.cantidadUnidades,
           c.m2totales        = d.m2totales
    FROM dbo.Consorcio c
    JOIN #dedup d ON d.nombre = c.nombre;

    INSERT INTO dbo.Consorcio (nombre, domicilio, cantidadUnidades, m2totales)
    SELECT d.nombre, d.domicilio, d.cantidadUnidades, d.m2totales
    FROM #dedup d
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Consorcio c WHERE c.nombre = d.nombre);
END
GO


-- #04 sp_ImportarPrestadoresServicio (XLSX)

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


-- #05 sp_Importar_Inquilino_propietarios_UF_CSV (CSV)

CREATE OR ALTER PROCEDURE dbo.sp_ImportarInquilinoPropietariosUFCSV
  @ruta NVARCHAR(500)
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('tempdb..#raw') IS NOT NULL DROP TABLE #raw;
    CREATE TABLE #raw(
      cbu_uf           VARCHAR(200) NULL,
      nombreConsorcio  VARCHAR(200) NULL,
      nroUF            VARCHAR(50)  NULL,
      tipo             VARCHAR(50)  NULL,
      departamento     VARCHAR(50)  NULL
    );

    -- 1) Primer intento: CRLF
    DECLARE @sql NVARCHAR(MAX)=N'
      BULK INSERT #raw
      FROM ' + QUOTENAME(@ruta,'''') + N'
      WITH (
        DATAFILETYPE    = ''char'',
        CODEPAGE        = ''65001'',
        FIELDTERMINATOR = ''|'',      -- separador pipe
        ROWTERMINATOR   = ''0x0d0a'', -- CRLF
        FIRSTROW        = 2,
        TABLOCK
      );';
    EXEC sys.sp_executesql @sql;

    -- 1.b) Si no leyó filas, reintenta con LF
    IF NOT EXISTS(SELECT 1 FROM #raw)
    BEGIN
      TRUNCATE TABLE #raw;
      SET @sql = N'
        BULK INSERT #raw
        FROM ' + QUOTENAME(@ruta,'''') + N'
        WITH (
          DATAFILETYPE    = ''char'',
          CODEPAGE        = ''65001'',
          FIELDTERMINATOR = ''|'',
          ROWTERMINATOR   = ''0x0a'', -- LF
          FIRSTROW        = 2,
          TABLOCK
        );';
      EXEC sys.sp_executesql @sql;
    END

    /* 2) Normalización idéntica a la que veníamos usando */
    ;WITH C AS (
      SELECT
        consorcio    = NULLIF(REPLACE(LTRIM(RTRIM(nombreConsorcio)),'"',''), ''),
        nroUF_int    = TRY_CONVERT(INT,
                          REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(nroUF)),'"',''),' ',''),'.',''),'-','')),
        departamento = NULLIF(LEFT(REPLACE(LTRIM(RTRIM(departamento)),'"',''), 10), ''),
        cbu_cvu      = NULLIF(CAST(
                          REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(cbu_uf)),'"',''),' ',''),'.',''),'-',''),
                                  CHAR(160),'') AS VARCHAR(30)),'')
      FROM #raw
    ),
    V AS (
      SELECT consorcio, nroUF_int, departamento, cbu_cvu
      FROM   C
      WHERE  consorcio IS NOT NULL
         AND nroUF_int IS NOT NULL
         AND (cbu_cvu IS NULL OR cbu_cvu NOT LIKE '%[^0-9]%') -- si viene, solo dígitos
    ),
    D AS (
      SELECT *,
             ROW_NUMBER() OVER (PARTITION BY consorcio, nroUF_int ORDER BY (SELECT NULL)) AS rn
      FROM   V
    ),
    SRC AS (
      SELECT
        cns.id      AS idConsorcio,
        d.nroUF_int AS numeroUnidad,
        d.departamento,
        d.cbu_cvu
      FROM D d
      JOIN dbo.Consorcio AS cns
        ON cns.nombre = d.consorcio
      WHERE d.rn = 1
    )
    MERGE dbo.UnidadFuncional AS T
    USING SRC AS S
      ON  T.idConsorcio  = S.idConsorcio
      AND T.numeroUnidad = S.numeroUnidad
    WHEN MATCHED THEN
      UPDATE SET
        T.departamento   = COALESCE(S.departamento, T.departamento),
        T.cbu_cvu_actual = COALESCE(S.cbu_cvu     , T.cbu_cvu_actual)
    WHEN NOT MATCHED BY TARGET THEN
      INSERT (idConsorcio, numeroUnidad, piso, departamento, coeficiente, m2_UF, cbu_cvu_actual)
      VALUES (S.idConsorcio, S.numeroUnidad, NULL, S.departamento, 0.0, 1, S.cbu_cvu);

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
  END CATCH
END;
GO



-- #06 sp_Importar_Inquilino_propietarios_datos_csv (CSV)

CREATE OR ALTER PROCEDURE dbo.SP_ImportarInquilinoPropietariosDatosCSV
         @ruta NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRAN;
    BEGIN TRY
        IF OBJECT_ID('tempdb..#Persona_raw') IS NOT NULL DROP TABLE #Persona_raw;

        CREATE TABLE #Persona_raw
        (
            nombre   VARCHAR(100) NULL,
            apellido VARCHAR(100) NULL,
            dni      VARCHAR(20)  NULL,
            email    VARCHAR(150) NULL,
            telefono VARCHAR(50)  NULL,
            cbu_cvu  VARCHAR(40)  NULL,
            tipotitularidad VARCHAR(11) NULL
        );

        DECLARE @sql NVARCHAR(500) =
        N'BULK INSERT #Persona_raw
        FROM' + QUOTENAME(@ruta,'''') + N' 
        WITH (
          DATAFILETYPE    = ''char'',
          CODEPAGE        = ''65001'',
          FIELDTERMINATOR = '';'',
          ROWTERMINATOR   = ''0x0d0a'',
          FIRSTROW        = 2,
          TABLOCK
        );';

        EXEC sp_executesql @sql;   

        ;WITH CTE AS (
          SELECT
            nombre   = NULLIF(REPLACE(LTRIM(RTRIM(nombre))  , '"',''), ''),
            apellido = NULLIF(REPLACE(LTRIM(RTRIM(apellido)), '"',''), ''),
            dni      = TRY_CONVERT(int, REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(dni)),' ',''),'.',''),'-','')),
            email    = NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(email))   , '"',''), ' ', ''), ''),
            telefono = NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(telefono)), '"',''), ' ', ''), ''),
            cbu_cvu  = NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(cbu_cvu)) , '"',''), ' ', ''), ''),
            tipoTitularidad = CASE UPPER(REPLACE(LTRIM(RTRIM(tipotitularidad)),'"',''))
                WHEN '1' THEN 'Inquilino'
                ELSE 'Propietario'
              END
          FROM #Persona_raw
        ),
        V AS (  -- validacion de constrains
          SELECT *
          FROM CTE
          WHERE dni BETWEEN 10000000 AND 99999999
            AND nombre   IS NOT NULL
            AND apellido IS NOT NULL
            AND (telefono IS NULL OR telefono NOT LIKE '%[^0-9]%')
            AND (cbu_cvu  IS NULL OR  cbu_cvu  NOT LIKE '%[^0-9]%')
        ),
        DUPS AS (      -- DNI DUplicados 
          SELECT dni, COUNT(*) AS cnt
          FROM V
          GROUP BY dni
          HAVING COUNT(*) > 1
        ),
        S AS (         -- filtro dni sin diplucados
          SELECT v.*
          FROM V v
          WHERE NOT EXISTS (SELECT 1 FROM DUPS d WHERE d.dni = v.dni)
        )
        MERGE dbo.Persona WITH (HOLDLOCK) AS t  -- HOLDFLOCK es similar a serializable 
        USING S AS s
           ON t.dni = s.dni
        WHEN MATCHED THEN
            UPDATE SET
                t.nombre          = s.nombre,
                t.apellido        = s.apellido,
                t.email           = s.email,
                t.telefono        = s.telefono,
                t.cbu_cvu         = s.cbu_cvu,
                t.tipoTitularidad = s.tipoTitularidad
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (nombre, apellido, dni, email, telefono, cbu_cvu, tipoTitularidad)
            VALUES (s.nombre, s.apellido, s.dni, s.email, s.telefono, s.cbu_cvu, s.tipoTitularidad);


    COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO



-- #07 sp_Importar_UF_por_consorcio (TXT)

CREATE OR ALTER PROCEDURE dbo.sp_Importar_UF_por_consorcio
    @ruta NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF OBJECT_ID('tempdb..#uf_txt_raw') IS NOT NULL DROP TABLE #uf_txt_raw;
        CREATE TABLE #uf_txt_raw(
          [Nombre del consorcio]       NVARCHAR(200) NULL,
          [nroUnidadFuncional]         NVARCHAR(50)  NULL,
          [Piso]                       NVARCHAR(20)  NULL,
          [departamento]               NVARCHAR(10)  NULL,
          [coeficiente]                NVARCHAR(20)  NULL,
          [m2_unidad_funcional]        NVARCHAR(20)  NULL,
          [bauleras]                   NVARCHAR(10)  NULL,
          [cochera]                    NVARCHAR(10)  NULL,
          [m2_baulera]                 NVARCHAR(20)  NULL,
          [m2_cochera]                 NVARCHAR(20)  NULL
        );

        DECLARE @sql NVARCHAR(MAX)=N'
BULK INSERT #uf_txt_raw
FROM ' + QUOTENAME(@ruta,'''') + N'
WITH (
  DATAFILETYPE    = ''char'',
  CODEPAGE        = ''65001'',
  FIELDTERMINATOR = ''\t'',
  ROWTERMINATOR   = ''0x0d0a'',
  FIRSTROW        = 2,
  TABLOCK
);';
        EXEC sys.sp_executesql @sql;

        -- Materializo S en #S (reutilizable)
        IF OBJECT_ID('tempdb..#S') IS NOT NULL DROP TABLE #S;
        SELECT
          c.id AS idConsorcio,
          TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(r.[nroUnidadFuncional])),''))      AS nroUF,
          TRY_CONVERT(SMALLINT, NULLIF(REPLACE(LTRIM(RTRIM(r.[Piso])),'PB',''),''))
                                                                                AS piso_int,
          NULLIF(LTRIM(RTRIM(r.[departamento])),'')                              AS depto,
          TRY_CONVERT(DECIMAL(3,1), REPLACE(NULLIF(LTRIM(RTRIM(r.[coeficiente])),''), ',', '.'))
                                                                                AS coef,
          TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(r.[m2_unidad_funcional])),''))     AS m2uf,
          CASE WHEN UPPER(LTRIM(RTRIM(r.[bauleras])))='SI' THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END
                                                                                AS baulera_bit,
          CASE WHEN UPPER(LTRIM(RTRIM(r.[cochera])))='SI' THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END
                                                                                AS cochera_bit,
          TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(r.[m2_baulera])),''))              AS m2_baulera,
          TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(r.[m2_cochera])),''))              AS m2_cochera
        INTO #S
        FROM #uf_txt_raw r
        JOIN dbo.Consorcio c
          ON c.nombre = LTRIM(RTRIM(r.[Nombre del consorcio]))
        WHERE LTRIM(RTRIM(r.[Nombre del consorcio])) IS NOT NULL
          AND TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(r.[nroUnidadFuncional])),'')) IS NOT NULL;

        -- MERGE UF
        MERGE dbo.UnidadFuncional AS T
        USING (
          SELECT idConsorcio,
                 numeroUnidad = nroUF,
                 piso         = piso_int,
                 departamento = depto,
                 coeficiente  = COALESCE(coef,0.0),
                 m2_UF        = COALESCE(m2uf,1)
          FROM #S
        ) AS X
        ON  T.idConsorcio = X.idConsorcio
        AND T.numeroUnidad = X.numeroUnidad
        WHEN MATCHED THEN
          UPDATE SET
            T.piso         = COALESCE(X.piso, T.piso),
            T.departamento = COALESCE(X.departamento, T.departamento),
            T.coeficiente  = COALESCE(X.coeficiente, T.coeficiente),
            T.m2_UF        = COALESCE(X.m2_UF, T.m2_UF)
        WHEN NOT MATCHED BY TARGET THEN
          INSERT (idConsorcio, numeroUnidad, piso, departamento, coeficiente, m2_UF, cbu_cvu_actual)
          VALUES (X.idConsorcio, X.numeroUnidad, X.piso, X.departamento, X.coeficiente, X.m2_UF, NULL);

        -- MERGE UnidadAccesoria (ahora sí, usando #S)
        ;WITH U AS (
          SELECT
            uf.idUF,
            s.baulera_bit,
            s.cochera_bit,
            COALESCE(s.m2_baulera,0) AS m2_baulera,
            COALESCE(s.m2_cochera,0) AS m2_cochera
          FROM #S s
          JOIN dbo.UnidadFuncional uf
            ON uf.idConsorcio = s.idConsorcio
           AND uf.numeroUnidad = s.nroUF
        )
        MERGE dbo.UnidadAccesoria AS TA
        USING U
        ON TA.idUnidadFuncional = U.idUF
        WHEN MATCHED THEN
          UPDATE SET
            TA.baulera    = U.baulera_bit,
            TA.cochera    = U.cochera_bit,
            TA.m2_baulera = U.m2_baulera,
            TA.m2_cochera = U.m2_cochera
        WHEN NOT MATCHED BY TARGET THEN
          INSERT (idUnidadFuncional, baulera, cochera, m2_baulera, m2_cochera)
          VALUES (U.idUF, U.baulera_bit, U.cochera_bit, U.m2_baulera, U.m2_cochera);

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

--08 Calcular facturas y estados financieros

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
