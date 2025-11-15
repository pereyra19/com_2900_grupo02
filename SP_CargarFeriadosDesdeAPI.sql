USE Com3900G02;
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

