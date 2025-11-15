USE Com3900G02;
GO

/*--------------------------------CREAMOS LOS ROLES---------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_Admin_General')
    CREATE ROLE rol_Admin_General;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_Admin_Bancario')
    CREATE ROLE rol_Admin_Bancario;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_Admin_Operativo')
    CREATE ROLE rol_Admin_Operativo;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_Sistemas')
    CREATE ROLE rol_Sistemas;
GO

/*----------------------------- USUARIOS------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'log_Admin_General')
    CREATE USER log_Admin_General WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'log_Admin_Bancario')
    CREATE USER log_Admin_Bancario WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'log_Admin_Operativo')
    CREATE USER log_Admin_Operativo WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'log_Sistemas')
    CREATE USER log_Sistemas WITHOUT LOGIN;
GO

/* Se asigna cada usuario al rol*/
EXEC sp_addrolemember N'rol_Admin_General',   N'log_Admin_General';
EXEC sp_addrolemember N'rol_Admin_Bancario',  N'log_Admin_Bancario';
EXEC sp_addrolemember N'rol_Admin_Operativo', N'log_Admin_Operativo';
EXEC sp_addrolemember N'rol_Sistemas',        N'log_Sistemas';
GO

/* ======================= PERMISOS por categoría ======================= */

/* ===== A) GENERACIÓN DE REPORTES → TODOS los perfiles (incluye Sistemas) */
IF OBJECT_ID('dbo.rpt_R1_FlujoCajaSemanal', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R1_FlujoCajaSemanal TO
        [rol_Admin_General], [rol_Admin_Bancario], [rol_Admin_Operativo], [rol_Sistemas];

IF OBJECT_ID('dbo.rpt_R2_RecaudacionMesDepto_XML', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R2_RecaudacionMesDepto_XML TO
        [rol_Admin_General], [rol_Admin_Bancario], [rol_Admin_Operativo], [rol_Sistemas];

IF OBJECT_ID('dbo.rpt_R3_RecaudacionPorProcedencia', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R3_RecaudacionPorProcedencia TO
        [rol_Admin_General], [rol_Admin_Bancario], [rol_Admin_Operativo], [rol_Sistemas];

IF OBJECT_ID('dbo.rpt_R4_Top5Meses_GastosIngresos', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R4_Top5Meses_GastosIngresos TO
        [rol_Admin_General], [rol_Admin_Bancario], [rol_Admin_Operativo], [rol_Sistemas];

IF OBJECT_ID('dbo.rpt_R5_TopMorosos', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R5_TopMorosos TO
        [rol_Admin_General], [rol_Admin_Bancario], [rol_Admin_Operativo], [rol_Sistemas];

IF OBJECT_ID('dbo.rpt_R6_PagosOrdinarios_XML', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.rpt_R6_PagosOrdinarios_GAP_XML TO
        [rol_Admin_General], [rol_Admin_Bancario], [rol_Admin_Operativo], [rol_Sistemas];


/* ===== B) IMPORTACIÓN BANCARIA → SOLO Administrativo Bancario */
IF OBJECT_ID('dbo.sp_Pagos_ImportarCSV', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.sp_Pagos_ImportarCSV TO [rol_Admin_Bancario];

IF OBJECT_ID('dbo.sp_Pagos_PendientesParaAsociar', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.sp_Pagos_PendientesParaAsociar TO [rol_Admin_Bancario];

/* ===== C) ACTUALIZACIÓN DE DATOS DE UF → General + Operativo */
IF OBJECT_ID('dbo.sp_Importar_UF_por_consorcio', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.sp_Importar_UF_por_consorcio
    TO [rol_Admin_General], [rol_Admin_Operativo];

IF OBJECT_ID('dbo.sp_Importar_Inquilino_propietarios_UF_CSV', 'P') IS NOT NULL
    GRANT EXECUTE ON dbo.sp_Importar_Inquilino_propietarios_UF_CSV
    TO [rol_Admin_General], [rol_Admin_Operativo];

