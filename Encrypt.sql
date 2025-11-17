USE Com3900G02;
GO

-------------------------------------------------------------
-- 1) MASTER KEY: crearla solo si no existe
-------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1
    FROM sys.symmetric_keys
    WHERE name = '##MS_DatabaseMasterKey##'
)
BEGIN
    PRINT 'Creando MASTER KEY de la base...';
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Password_Fuerte_2025!';
END
ELSE
BEGIN
    PRINT 'MASTER KEY ya existía, no se vuelve a crear.';
END
GO

OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Password_Fuerte_2025!';
GO

-------------------------------------------------------------
-- 2) CERTIFICADO: si existe lo dropeo, luego lo creo de nuevo
-------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM sys.certificates
    WHERE name = 'Cert_DatosSensibles'
)
BEGIN
    DROP CERTIFICATE Cert_DatosSensibles;
END
GO

CREATE CERTIFICATE Cert_DatosSensibles
    WITH SUBJECT = 'Certificado para cifrado de datos sensibles - TP Com3900G02';
GO

-------------------------------------------------------------
-- 3) SYMMETRIC KEY: igual, la dropeo si existe y la recreo
-------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM sys.symmetric_keys
    WHERE name = 'Key_DatosSensibles'
)
BEGIN
    DROP SYMMETRIC KEY Key_DatosSensibles;
END
GO

CREATE SYMMETRIC KEY Key_DatosSensibles
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE Cert_DatosSensibles;
GO

-------------------------------------------------------------
-- 4) Agregar columnas VARBINARY solo si no existen
-------------------------------------------------------------
IF COL_LENGTH('dbo.Persona', 'nombre_encrypted') IS NULL
BEGIN
    ALTER TABLE dbo.Persona
    ADD nombre_encrypted VARBINARY(256) NULL;
END;

IF COL_LENGTH('dbo.Persona', 'apellido_encrypted') IS NULL
BEGIN
    ALTER TABLE dbo.Persona
    ADD apellido_encrypted VARBINARY(256) NULL;
END;

IF COL_LENGTH('dbo.Persona', 'email_encrypted') IS NULL
BEGIN
    ALTER TABLE dbo.Persona
    ADD email_encrypted VARBINARY(256) NULL;
END;

IF COL_LENGTH('dbo.Persona', 'telefono_encrypted') IS NULL
BEGIN
    ALTER TABLE dbo.Persona
    ADD telefono_encrypted VARBINARY(256) NULL;
END;
GO

CREATE OR ALTER TRIGGER TR_Persona_Encrypt
ON dbo.Persona
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Abrimos la symmetric key para esta operación
    OPEN SYMMETRIC KEY Key_DatosSensibles
        DECRYPTION BY CERTIFICATE Cert_DatosSensibles;

    UPDATE p
    SET
        nombre_encrypted = CASE 
            WHEN i.nombre IS NOT NULL
            THEN EncryptByKey(Key_GUID('Key_DatosSensibles'), CONVERT(NVARCHAR(100), i.nombre))
            ELSE p.nombre_encrypted
        END,
        apellido_encrypted = CASE 
            WHEN i.apellido IS NOT NULL
            THEN EncryptByKey(Key_GUID('Key_DatosSensibles'), CONVERT(NVARCHAR(100), i.apellido))
            ELSE p.apellido_encrypted
        END,
        email_encrypted = CASE 
            WHEN i.email IS NOT NULL
            THEN EncryptByKey(Key_GUID('Key_DatosSensibles'), CONVERT(NVARCHAR(100), i.email))
            ELSE p.email_encrypted
        END,
        telefono_encrypted = CASE 
            WHEN i.telefono IS NOT NULL
            THEN EncryptByKey(Key_GUID('Key_DatosSensibles'), CONVERT(NVARCHAR(20), i.telefono))
            ELSE p.telefono_encrypted
        END,

        -- Blanqueo de columnas originales
        nombre   = NULL,
        apellido = NULL,
        email    = NULL,
        telefono = NULL
    FROM dbo.Persona p
    JOIN inserted i
      ON p.id = i.id;

    CLOSE SYMMETRIC KEY Key_DatosSensibles;
END;
GO
