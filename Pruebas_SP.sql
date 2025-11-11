-----------------------------------------------------------------------
/* Si estan mal la ruta del archivo Probablemente se desconecte el motor 
entonces -> (win + R) escribis services.msc y buscar SQL Server (MSSQLSERVER)
y reinicias 
*/
--------------------------------------------------------------------


USE Com3900G02;
GO

-- IMPORTACION 

--config para trabjar con xlsx
EXEC sys.sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sys.sp_configure 'Ad Hoc Distributed Queries', 1; RECONFIGURE;
EXEC master.dbo.sp_MSset_oledb_prop N'Microsoft.ACE.OLEDB.16.0',N'AllowInProcess',1;
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
  @FilePath = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\Servicios.Servicios.json',
  @Year     = 2025;
SELECT COUNT(*) AS expensas FROM dbo.Expensa;
SELECT COUNT(*) AS detalle_expensa FROM dbo.DetalleExpensa;
GO

-- 6) PAGOS (CSV) -> ya debería matchear CBU→UF
EXEC dbo.sp_Pagos_ImportarCSV
  @FilePath = N'C:\Users\perey\OneDrive\Escritorio\com3900G02\com_3641_grupo02\archivos\pagos_consorcios.csv';
SELECT COUNT(*) AS pagos FROM dbo.Pago;
GO



-- REPORTE #01 
  EXEC dbo.rpt_R1_FlujoCajaSemanal '2025-01-01','2025-12-31', NULL;

-- REPORTE #02 
EXEC dbo.rpt_R2_RecaudacionMesDepto_XML '2025-01-01','2025-12-31', NULL;


-- REPORTE #03
EXEC dbo.rpt_R3_RecaudacionPorProcedencia '2025-01-01','2025-12-31', NULL;


-- REPORTE #04 
EXEC dbo.rpt_R4_Top5Meses_GastosIngresos '2025-01-01','2025-12-31', NULL;

-- REPORTE #05
EXEC dbo.rpt_R5_TopMorosos '2025-12-31', NULL, 3;

-- REPORTE #06
EXEC dbo.rpt_R6_PagosOrdinarios_GAP_XML '2025-01-01','2025-12-31', NULL;



















