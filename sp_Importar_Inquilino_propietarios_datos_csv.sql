CREATE OR ALTER PROCEDURE dbo.sp_Importar_Inquilino_propietarios_datos_csv
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