USE Com3900G02;
GO

--Pagos
EXEC dbo.sp_CargarPagosDesdeCsv N'C:\Users\Spooky\Documents\consorcios\pagos_consorcios.csv'

SELECT * FROM Pago
--DELETE FROM Consorcio

--Consorcios
EXEC dbo.sp_ImportarConsorcios
    @FilePath  = N'C:\Users\Spooky\Documents\consorcios\d.xlsx',
    @SheetName = N'Consorcios$';
GO
SELECT * FROM Consorcio

--PrestadoresDeServicio
EXEC dbo.sp_ImportarPrestadoresServicio
  @FilePath  = N'C:\Users\Spooky\Documents\consorcios\d.xlsx',
  @SheetName = N'Proveedores$';

SELECT * FROM PrestadorServicio

--Personas
EXEC dbo.sp_Importar_Inquilino_propietarios_datos_csv
    @ruta = N'C:\Users\Spooky\Documents\consorcios\Inquilino-propietarios-datos.csv';

-- uf
EXEC dbo.sp_Importar_UF_por_consorcio_TXT
    @ruta = N'C:\Users\Spooky\Documents\consorcios\UF por consorcio.txt';

-- Personas - UF
EXEC dbo.sp_Importar_Inquilino_propietarios_UF_CSV
    @ruta = N'C:\Users\Spooky\Documents\consorcios\Inquilino-propietarios-UF.csv';

EXEC dbo.SPImportacionServicios
    @FilePath = N'C:\Users\Spooky\Documents\consorcios\Servicios.Servicios.json',
    @Year = 2025;
GO

SELECT * FROM Expensa
 