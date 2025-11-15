USE Com3900G02;
GO

-- Pago: por UF y fecha
CREATE NONCLUSTERED INDEX IX_Pago_UF_Fecha
ON dbo.Pago (nroUnidadFuncional, fechaPago)
INCLUDE (monto, idDePago, cbu);
GO

-- PagoExpensa: enlaces pago<->expensa
CREATE NONCLUSTERED INDEX IX_PagoExpensa_Pago
ON dbo.PagoExpensa (idPago, idExpensa);
GO

CREATE NONCLUSTERED INDEX IX_PagoExpensa_Expensa
ON dbo.PagoExpensa (idExpensa, idPago);
GO

-- DetalleExpensa: por expensa y categoría
CREATE NONCLUSTERED INDEX IX_DetalleExpensa_Expensa_Categoria
ON dbo.DetalleExpensa (idExpensa, categoria)
INCLUDE (tipo, importe, idPrestadorServicio);
GO

-- DetalleExpensa: por prestadorServicio
CREATE NONCLUSTERED INDEX IX_DetalleExpensa_Prestador
ON dbo.DetalleExpensa (idPrestadorServicio)
INCLUDE (idExpensa, importe, categoria, tipo);
GO

-- UnidadFuncional: por consorcio
CREATE NONCLUSTERED INDEX IX_UF_Consorcio
ON dbo.UnidadFuncional (idConsorcio)
INCLUDE (idUF, numeroUnidad, departamento, coeficiente);
GO

-- PrestadorServicio: por consorcio y tipo
CREATE NONCLUSTERED INDEX IX_Prestador_Consorcio_Tipo
ON dbo.PrestadorServicio (idConsorcio, tipoServicio)
INCLUDE (id, nombre, cuenta);
GO

