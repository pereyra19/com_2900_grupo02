-----------------------------------------------------------------------
/* Si estan mal la ruta del archivo Probablemente se desconecte el motor 
entonces -> (win + R) escribis services.msc y buscar SQL Server (MSSQLSERVER)
y reinicias 
*/
--------------------------------------------------------------------




------------------------------------ IMPORTACION ------------------------------------------------
USE Com3900G02;
GO
--config para trabjar con xlsx
EXEC sys.sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sys.sp_configure 'Ad Hoc Distributed Queries', 1; RECONFIGURE;
EXEC master.dbo.sp_MSset_oledb_prop N'Microsoft.ACE.OLEDB.16.0',N'AllowInProcess',0; -- si no funciona con 1 pone 0 
EXEC master.dbo.sp_MSset_oledb_prop N'Microsoft.ACE.OLEDB.16.0',N'DynamicParameters',1;


-- 1) CONSORCIOS (XLSX)  - hoja: Consorcios$
EXEC dbo.sp_ImportarConsorcios
  @FilePath  = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\datos varios.xlsx',
  @SheetName = N'Consorcios$';
SELECT COUNT(*) AS consorcios FROM dbo.Consorcio;
GO
-- chequeo con el xlsx
SELECT nombre, domicilio, cantidadUnidades, m2totales
FROM dbo.Consorcio
ORDER BY nombre;

-- 1.2) PRESTADORES DE SERVICIO (XLSX)  - hoja: Proveedores
EXEC dbo.sp_ImportarPrestadoresServicio
  @FilePath  = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\datos varios.xlsx',
  @SheetName = N'Proveedores$';
SELECT * FROM dbo.PrestadorServicio;
GO

-- 2) UF POR CONSORCIO (TXT) - llena UF (nro, coef, etc...) 
EXEC dbo.sp_Importar_UF_por_consorcio
  @ruta = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\UF por consorcio.txt';
SELECT COUNT(*) AS uf FROM dbo.UnidadFuncional;
SELECT COUNT(*) AS uf_accesorias FROM dbo.UnidadAccesoria;
GO

-- 3) UF + CBU (CSV) - setea cbu_cvu_actual en la UF
EXEC dbo.sp_ImportarInquilinoPropietariosUFCSV
  @ruta = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\Inquilino-propietarios-UF.csv';
-- chequeo rápido: cuántas UF quedaron con CBU asignado
SELECT COUNT(*) AS uf_con_cbu FROM dbo.UnidadFuncional WHERE cbu_cvu_actual IS NOT NULL;
GO

-- 4) PERSONAS (CSV)
EXEC dbo.SP_ImportarInquilinoPropietariosDatosCSV
  @ruta = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\Inquilino-propietarios-datos.csv';
SELECT COUNT(*) AS personas FROM dbo.Persona;
GO

-- 5) SERVICIOS → genera EXPENSAS y DETALLEEXPENSA (JSON)
EXEC dbo.sp_ImportacionServicios
  @RutaArchivo = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\Servicios.Servicios.json',
  @Anio        = 2025;
SELECT COUNT(*) AS expensas FROM dbo.Expensa;
SELECT COUNT(*) AS detalle_expensa FROM dbo.DetalleExpensa;
GO

-- 6) PAGOS (CSV) -> ya debería matchear CBU→UF
EXEC dbo.sp_Pagos_ImportarCSV
  @FilePath = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\pagos_consorcios.csv';
SELECT COUNT(*) AS pagos FROM dbo.Pago;
GO

--------------------------------------------API------------------------------------------------------------------

--Se cargan los feriados de cada año en una tabla Feriados

EXEC dbo.CargarFeriados 2024;
EXEC dbo.CargarFeriados 2025;
SELECT * From Feriados;
GO

-------------------------------------------GENERAR-FACTURAS-POR-PERIODO-------------------------------------------


--Si es feriado, deberia generar  las facturas al siguiente dia, revisando la tabla con datos cargados desde la api
EXEC dbo.sp_GenerarFacturasYEstados 
    @Anio = 2025,
    @Mes = 5,
    @FechaEmision ='2025-05-25';


SELECT * FROM FacturaExpensa WHERE fechaEmision = '2025-05-26';
SELECT * FROM FacturaExpensa;
SELECT * FROM EstadoFinanciero;

-----------------------------------------

EXEC dbo.sp_GenerarFacturasYEstados 
    @Anio = 2025,
    @Mes = 6,
    @FechaEmision ='2025-06-25';


SELECT * FROM FacturaExpensa WHERE fechaEmision = '2025-06-25';
SELECT * FROM FacturaExpensa;
SELECT * FROM EstadoFinanciero;

--------------------------------------------DESENCRIPTADO---------------------------------------------------------
USE Com3900G02;
GO

--Datos encriptados de persona
SELECT nombre_encrypted, apellido_encrypted, email_encrypted, telefono_encrypted from persona


--Los desencriptamos
OPEN SYMMETRIC KEY Key_DatosSensibles
    DECRYPTION BY CERTIFICATE Cert_DatosSensibles;
GO

SELECT
    p.id,
    CONVERT(NVARCHAR(100), DecryptByKey(p.nombre_encrypted))   AS nombre,
    CONVERT(NVARCHAR(100), DecryptByKey(p.apellido_encrypted)) AS apellido,
    CONVERT(NVARCHAR(100), DecryptByKey(p.email_encrypted))    AS email,
    CONVERT(NVARCHAR(20),  DecryptByKey(p.telefono_encrypted)) AS telefono,
    p.cbu_cvu
FROM dbo.Persona p;
GO

CLOSE SYMMETRIC KEY Key_DatosSensibles;
GO



---------------------------------------------REPORTES-------------------------------------------------------------

--  se ejecuta como "Administrador General"

EXECUTE AS LOGIN = 'log_Admin_General';
    -- #01 – Flujo de caja semanal
    EXEC dbo.rpt_R1_FlujoCajaSemanal @FechaDesde  = '2025-01-01', @FechaHasta  = '2025-12-31',@IdConsorcio = NULL;
    GO

    -- #02 – Recaudación por mes y departamento (XML)
    EXEC dbo.rpt_R2_RecaudacionMesDepto_XML  @FechaDesde  = '2025-01-01', @FechaHasta  = '2025-12-31', @IdConsorcio = NULL;
    GO

    -- #03 – Recaudación por procedencia (ordinario / extraordinario)
    EXEC dbo.rpt_R3_RecaudacionPorProcedencia  @FechaDesde  = '2025-01-01', @FechaHasta  = '2025-12-31', @IdConsorcio = NULL;
    GO

    -- #04 – Top 5 meses con mayores gastos / ingresos
    EXEC dbo.rpt_R4_Top5Meses_GastosIngresos  @FechaDesde  = '2025-01-01', @FechaHasta = '2025-12-31', @IdConsorcio = NULL;
    GO

    -- #05 – Top morosos
    EXEC dbo.rpt_R5_TopMorosos @FechaCorte  = '2025-12-31', @IdConsorcio = NULL, @TopN = 3;
    GO

    -- #06 – Pagos ordinarios por UF + días hasta el siguiente (XML)
    EXEC dbo.rpt_R6_PagosOrdinarios_XML @FechaDesde  = '2025-01-01', @FechaHasta  = '2025-12-31', @IdConsorcio = NULL;
    GO
REVERT;
GO

--Se ejecuta como Administrativo Bancario
EXECUTE AS LOGIN = 'log_Admin_Bancario';
    -- Importación de pagos desde el CSV bancario
    EXEC dbo.sp_Pagos_ImportarCSV 
        @FilePath = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\pagos_consorcios.csv';
REVERT;
GO

-- Se ejecuta como Administrativo Operativo
EXECUTE AS LOGIN = 'log_Admin_Operativo';
    -- Importar TXT
    EXEC dbo.sp_Importar_UF_por_consorcio 
        @ruta = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\UF por consorcio.txt';

    -- Importar archivo de Inquilino-propietarios-UF
    EXEC dbo.sp_ImportarInquilinoPropietariosUFCSV 
        @ruta = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\Inquilino-propietarios-UF.csv';
REVERT;
GO

-- Se ejecuta como Sistemas
EXECUTE AS LOGIN = 'log_Sistemas';
    -- Reporte 1
    EXEC dbo.rpt_R1_FlujoCajaSemanal @FechaDesde  = '2025-01-01', @FechaHasta  = '2025-12-31', @IdConsorcio = NULL;

    -- Reporte 6
    EXEC dbo.rpt_R6_PagosOrdinarios_XML  @FechaDesde  = '2025-01-01', @FechaHasta  = '2025-12-31',  @IdConsorcio = NULL;
REVERT;
GO








