USE Com3900G02;
GO

CREATE OR ALTER FUNCTION dbo.fn_NormalizarImporte
(
    @texto NVARCHAR(50)
)
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @limpio NVARCHAR(50);
    DECLARE @len INT, @posUltimoPunto INT, @posUltimaComa INT;
    DECLARE @sepDecimal NCHAR(1);

    -- saco espacios
    SET @limpio = LTRIM(RTRIM(@texto));
    IF @limpio IS NULL OR @limpio = '' RETURN NULL;

    SET @limpio = REPLACE(@limpio, ' ', '');

    SET @len = LEN(@limpio);

    -- posición del último punto y de la última coma
    SET @posUltimoPunto  = CASE 
                             WHEN CHARINDEX('.', @limpio) = 0 THEN 0
                             ELSE @len - CHARINDEX('.', REVERSE(@limpio)) + 1
                           END;

    SET @posUltimaComa   = CASE 
                             WHEN CHARINDEX(',', @limpio) = 0 THEN 0
                             ELSE @len - CHARINDEX(',', REVERSE(@limpio)) + 1
                           END;

    -- determino qué uso como separador decimal
    IF @posUltimoPunto = 0 AND @posUltimaComa = 0
        SET @sepDecimal = NULL;       -- entero, sin decimales
    ELSE IF @posUltimoPunto = 0
        SET @sepDecimal = ',';        -- solo comas
    ELSE IF @posUltimaComa = 0
        SET @sepDecimal = '.';        -- solo puntos
    ELSE IF @posUltimoPunto > @posUltimaComa
        SET @sepDecimal = '.';        -- el último símbolo es punto
    ELSE
        SET @sepDecimal = ',';        -- el último símbolo es coma

    -- normalizo a formato tipo 123456.78
    IF @sepDecimal = '.'
    BEGIN
        -- punto decimal -> saco todas las comas (miles)
        SET @limpio = REPLACE(@limpio, ',', '');
    END
    ELSE IF @sepDecimal = ','
    BEGIN
        -- coma decimal -> saco puntos y después cambio coma por punto
        SET @limpio = REPLACE(@limpio, '.', '');
        SET @limpio = REPLACE(@limpio, ',', '.');
    END
    ELSE
    BEGIN
        -- no hay sep. decimal: dejo solo dígitos
        SET @limpio = REPLACE(REPLACE(@limpio, '.', ''), ',', '');
    END

    RETURN TRY_CAST(@limpio AS DECIMAL(12,2));
END;
GO


CREATE OR ALTER FUNCTION dbo.fn_MapearConceptoTipoServicio
(
    @concepto NVARCHAR(80)
)
RETURNS VARCHAR(100)
AS
BEGIN
    DECLARE @resultado VARCHAR(100);

    SET @resultado = 
        CASE LTRIM(RTRIM(@concepto))
            WHEN 'BANCARIOS'               THEN 'GASTOS BANCARIOS'
            WHEN 'LIMPIEZA'                THEN 'GASTOS DE LIMPIEZA'
            WHEN 'ADMINISTRACION'          THEN 'GASTOS DE ADMINISTRACION'
            WHEN 'SEGUROS'                 THEN 'SEGUROS'
            WHEN 'GASTOS GENERALES'        THEN 'GASTOS GENERALES'
            WHEN 'SERVICIOS PUBLICOS-Agua' THEN 'SERVICIOS PUBLICOS'
            WHEN 'SERVICIOS PUBLICOS-Luz'  THEN 'SERVICIOS PUBLICOS'
            ELSE 'EXTRAORDINARIO'
        END;

    RETURN @resultado;
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_MapearConceptoCategoria
(
    @concepto NVARCHAR(80)
)
RETURNS VARCHAR(50)
AS
BEGIN
    DECLARE @resultado VARCHAR(50);

    IF LTRIM(RTRIM(@concepto)) IN (
        'BANCARIOS',
        'LIMPIEZA',
        'ADMINISTRACION',
        'SEGUROS',
        'GASTOS GENERALES',
        'SERVICIOS PUBLICOS-Agua',
        'SERVICIOS PUBLICOS-Luz'
    )
        SET @resultado = 'ORDINARIO';
    ELSE
        SET @resultado = 'EXTRAORDINARIO';

    RETURN @resultado;
END;
GO


CREATE OR ALTER FUNCTION dbo.EsFeriado(@fecha DATE)
RETURNS BIT
AS
BEGIN
    DECLARE @resultado BIT = 0;

    IF EXISTS (SELECT 1 FROM dbo.Feriados WHERE fecha = @fecha)
        SET @resultado = 1;

    RETURN @resultado;
END;
GO