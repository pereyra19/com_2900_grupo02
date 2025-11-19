USE master;
GO

-- elimina login 
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'log_Admin_General')
    DROP LOGIN log_Admin_General;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'log_Admin_Bancario')
    DROP LOGIN log_Admin_Bancario;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'log_Admin_Operativo')
    DROP LOGIN log_Admin_Operativo;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'log_Sistemas')
    DROP LOGIN log_Sistemas;
GO

-- Crear logins con contraseñas fijas (sin caducidad ni política de complejidad)
CREATE LOGIN log_Admin_General   WITH PASSWORD = 'AdminGeneral',  CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
CREATE LOGIN log_Admin_Bancario  WITH PASSWORD = 'AdminBancario', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
CREATE LOGIN log_Admin_Operativo WITH PASSWORD = 'AdminOperativo',CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
CREATE LOGIN log_Sistemas        WITH PASSWORD = 'Sistemas',      CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
GO

/* CHECK_POLICY = OFF  SQL no revisa las "normas" de contraseña (Mayusculas,longitud,etc)
 CHECK_EXPIRATION = OFF; la contra no expira                                             */

-- Conceder permisos de BULK a los logins que importan archivos
ALTER SERVER ROLE bulkadmin ADD MEMBER log_Admin_Bancario;
ALTER SERVER ROLE bulkadmin ADD MEMBER log_Admin_Operativo;
GO


USE Com3900G02;
GO

-- eliminamos usuarios y roles 
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'log_Admin_General')   DROP USER log_Admin_General;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'log_Admin_Bancario')  DROP USER log_Admin_Bancario;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'log_Admin_Operativo') DROP USER log_Admin_Operativo;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'log_Sistemas')        DROP USER log_Sistemas;
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_Admin_General'   AND type = 'R') DROP ROLE rol_Admin_General;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_Admin_Bancario'  AND type = 'R') DROP ROLE rol_Admin_Bancario;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_Admin_Operativo' AND type = 'R') DROP ROLE rol_Admin_Operativo;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_Sistemas'        AND type = 'R') DROP ROLE rol_Sistemas;
GO

--
CREATE ROLE rol_Admin_General;
CREATE ROLE rol_Admin_Bancario;
CREATE ROLE rol_Admin_Operativo;
CREATE ROLE rol_Sistemas;
GO

-- Crear usuarios asociados a los logins
CREATE USER log_Admin_General   FOR LOGIN log_Admin_General;
CREATE USER log_Admin_Bancario  FOR LOGIN log_Admin_Bancario;
CREATE USER log_Admin_Operativo FOR LOGIN log_Admin_Operativo;
CREATE USER log_Sistemas        FOR LOGIN log_Sistemas;
GO

-- Asignar usuarios a sus roles
ALTER ROLE rol_Admin_General   ADD MEMBER log_Admin_General;
ALTER ROLE rol_Admin_Bancario  ADD MEMBER log_Admin_Bancario;
ALTER ROLE rol_Admin_Operativo ADD MEMBER log_Admin_Operativo;
ALTER ROLE rol_Sistemas        ADD MEMBER log_Sistemas;
GO


-- permisos de reportes a todos los roles 
IF OBJECT_ID('dbo.rpt_R1_FlujoCajaSemanal', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R1_FlujoCajaSemanal TO rol_Admin_General, rol_Admin_Bancario, rol_Admin_Operativo, rol_Sistemas;
IF OBJECT_ID('dbo.rpt_R2_RecaudacionMesDepto_XML', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R2_RecaudacionMesDepto_XML TO rol_Admin_General, rol_Admin_Bancario, rol_Admin_Operativo, rol_Sistemas;
IF OBJECT_ID('dbo.rpt_R3_RecaudacionPorProcedencia', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R3_RecaudacionPorProcedencia TO rol_Admin_General, rol_Admin_Bancario, rol_Admin_Operativo, rol_Sistemas;
IF OBJECT_ID('dbo.rpt_R4_Top5Meses_GastosIngresos', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R4_Top5Meses_GastosIngresos TO rol_Admin_General, rol_Admin_Bancario, rol_Admin_Operativo, rol_Sistemas;
IF OBJECT_ID('dbo.rpt_R5_TopMorosos', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R5_TopMorosos TO rol_Admin_General, rol_Admin_Bancario, rol_Admin_Operativo, rol_Sistemas;
IF OBJECT_ID('dbo.rpt_R6_PagosOrdinarios_XML', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R6_PagosOrdinarios_XML TO rol_Admin_General, rol_Admin_Bancario, rol_Admin_Operativo, rol_Sistemas;


-- Bancario importa pagos
IF OBJECT_ID('dbo.sp_Pagos_ImportarCSV', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.sp_Pagos_ImportarCSV TO rol_Admin_Bancario;

-- General y Operativo actualizan datos de UF
IF OBJECT_ID('dbo.sp_Importar_UF_por_consorcio', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.sp_Importar_UF_por_consorcio TO rol_Admin_General, rol_Admin_Operativo;

-- General y Operativo actualizan CBU de UF
IF OBJECT_ID('dbo.sp_ImportarInquilinoPropietariosUFCSV', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.sp_ImportarInquilinoPropietariosUFCSV TO rol_Admin_General, rol_Admin_Operativo;
GO


--Permisos sobre la key para que ejecute los reportes
GRANT CONTROL ON CERTIFICATE::Cert_DatosSensibles TO log_Admin_General;
GRANT VIEW DEFINITION ON SYMMETRIC KEY::Key_DatosSensibles TO log_Admin_General;
GRANT REFERENCES ON SYMMETRIC KEY::Key_DatosSensibles TO log_Admin_General;
GO
