CREATE OR ALTER PROCEDURE dbo.sp_Importar_Inquilino_propietarios_UF_CSV
  @ruta NVARCHAR(500)  
AS
BEGIN
  SET NOCOUNT ON;

  BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('tempdb..#raw') IS NOT NULL DROP TABLE #raw;
    CREATE TABLE #raw (
      cbu_uf           VARCHAR(100) NULL,
      nombreConsorcio  VARCHAR(200) NULL,
      nroUF            VARCHAR(50)  NULL,
      tipo             VARCHAR(50)  NULL,   -- no se usa aquí
      departamento     VARCHAR(50)  NULL
    );

    DECLARE @sql NVARCHAR(MAX) =
      N'BULK INSERT #raw
         FROM ' + QUOTENAME(@ruta,'''') + N'
         WITH (
           DATAFILETYPE    = ''char'',
           CODEPAGE        = ''65001'',
           FIELDTERMINATOR = '';'',
           ROWTERMINATOR   = ''0x0d0a'',   -- usar ''0x0a'' si el archivo es LF
           FIRSTROW        = 2,
           TABLOCK
         );';
    EXEC sys.sp_executesql @sql;


    ;WITH C AS (  -- normalizar tablas 
      SELECT
        consorcio    = NULLIF(REPLACE(LTRIM(RTRIM(nombreConsorcio)),'"',''), ''),
        nroUF_int    = TRY_CONVERT(INT,REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(nroUF)),'"',''),' ',''),'.',''),'-','')),
        departamento = NULLIF(LEFT(REPLACE(LTRIM(RTRIM(departamento)),'"',''), 10), ''),
        cbu_cvu      = NULLIF(CAST(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(cbu_uf)),'"',''),' ',''),'.',''),'-',''),CHAR(160),'') AS VARCHAR(30)),'')
      FROM #raw
    ),
    V AS ( -- filtra tablas por constrains 
      SELECT consorcio, nroUF_int, departamento, cbu_cvu
      FROM   C
      WHERE  consorcio IS NOT NULL
         AND nroUF_int IS NOT NULL
         AND (cbu_cvu IS NULL OR cbu_cvu NOT LIKE '%[^0-9]%') -- solo dígitos si viene
    ),
    D AS (  -- una por clave (consorcio, nroUF)
      SELECT *,
             ROW_NUMBER() OVER (PARTITION BY consorcio, nroUF_int ORDER BY (SELECT NULL)) AS rn
      FROM   V
    ),
    SRC AS (  -- mapea nombre de consorcio → idConsorcio
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

    /* 3) UPSERT en dbo.UnidadFuncional por (idConsorcio, numeroUnidad)
          MATCHED: actualiza departamento y cbu_cvu_actual
          NOT MATCHED: inserta con placeholders (piso=NULL, coeficiente=0.0, m2_UF=1) */
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
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
  END CATCH
END
GO